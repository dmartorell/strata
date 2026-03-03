import Foundation

// MARK: - Response Models

struct LoginResponse: Decodable {
    let token: String
}

struct ProcessResponse: Decodable {
    let job_id: String
}

struct JobStatusResponse: Decodable {
    let status: String
}

struct JobResult: Sendable {
    var zipData: Data? = nil
    var status: String = ""
}

struct UsageResponse: Decodable {
    let month: String
    let songs_processed: Int
    let gpu_seconds: Double
    let estimated_cost_usd: Double
}

// MARK: - HTTP Transport Protocol (testable)

/// Abstracción sobre URLSession para permitir mocks en tests
protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

// MARK: - Multipart Helper

struct MultipartRequest {
    let boundary: String
    private var body = Data()

    init() {
        boundary = "Boundary-\(UUID().uuidString)"
    }

    mutating func addFile(name: String, fileName: String, mimeType: String, data: Data) {
        let boundaryLine = "--\(boundary)\r\n"
        let disposition = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n"
        let contentType = "Content-Type: \(mimeType)\r\n\r\n"

        body.append(Data(boundaryLine.utf8))
        body.append(Data(disposition.utf8))
        body.append(Data(contentType.utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    mutating func addField(name: String, value: String) {
        let boundaryLine = "--\(boundary)\r\n"
        let disposition = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        body.append(Data(boundaryLine.utf8))
        body.append(Data(disposition.utf8))
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    func finalize() -> Data {
        var finalBody = body
        let closing = "--\(boundary)--\r\n"
        finalBody.append(Data(closing.utf8))
        return finalBody
    }

    var contentTypeHeader: String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

// MARK: - Import API Protocol (testability)

protocol ImportAPIClientProtocol: Sendable {
    func uploadAudio(fileData: Data, fileName: String, mimeType: String, token: String) async throws -> String
    func uploadURL(urlString: String, token: String) async throws -> String
    func pollJobStatus(jobId: String, token: String, intervalSeconds: Double, maxAttempts: Int) async throws -> JobResult
}

extension ImportAPIClientProtocol {
    func pollJobStatus(jobId: String, token: String) async throws -> JobResult {
        try await pollJobStatus(jobId: jobId, token: token, intervalSeconds: 3, maxAttempts: 60)
    }
}

extension APIClient: ImportAPIClientProtocol {}

// MARK: - APIClient

struct APIClient: Sendable {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    init(session: URLSession) {
        self.transport = session
    }

    // MARK: - Public API

    /// POST /auth/login — obtener JWT con contraseña
    func login(password: String) async throws -> String {
        let endpoint = APIEndpoint.login
        var request = makeRequest(endpoint: endpoint, token: nil)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["password": password])

        let (data, response) = try await transport.data(for: request)
        try checkResponse(response, isAuthenticated: false)

        let decoded = try decode(LoginResponse.self, from: data)
        return decoded.token
    }

    /// POST /auth/renew — renovar JWT
    func renewToken(current: String) async throws -> String {
        let endpoint = APIEndpoint.renew
        let request = makeRequest(endpoint: endpoint, token: current)

        let (data, response) = try await transport.data(for: request)
        try checkResponse(response, isAuthenticated: true)

        let decoded = try decode(LoginResponse.self, from: data)
        return decoded.token
    }

    /// POST /process-file — upload multipart de audio, devuelve job_id
    func uploadAudio(fileData: Data, fileName: String, mimeType: String, token: String) async throws -> String {
        let endpoint = APIEndpoint.processFile
        var multipart = MultipartRequest()
        multipart.addFile(name: "audio_file", fileName: fileName, mimeType: mimeType, data: fileData)
        let body = multipart.finalize()

        var request = makeRequest(endpoint: endpoint, token: token)
        request.setValue(multipart.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await transport.data(for: request)
        try checkResponse(response, isAuthenticated: true)

        let decoded = try decode(ProcessResponse.self, from: data)
        return decoded.job_id
    }

    /// POST /process-url — envía URL de YouTube, devuelve job_id
    func uploadURL(urlString: String, token: String) async throws -> String {
        let endpoint = APIEndpoint.processURL
        var request = makeRequest(endpoint: endpoint, token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["url": urlString])

        let (data, response) = try await transport.data(for: request)
        try checkResponse(response, isAuthenticated: true)

        let decoded = try decode(ProcessResponse.self, from: data)
        return decoded.job_id
    }

    /// GET /result/{jobId} — polling hasta completed o error
    /// - Parameters:
    ///   - intervalSeconds: segundos entre intentos (default 3, override en tests con 0)
    ///   - maxAttempts: máximo de intentos (default 60, override en tests)
    func pollJobStatus(
        jobId: String,
        token: String,
        intervalSeconds: Double = 3,
        maxAttempts: Int = 60
    ) async throws -> JobResult {
        let endpoint = APIEndpoint.result(jobId: jobId)
        let request = makeRequest(endpoint: endpoint, token: token)

        for _ in 0..<maxAttempts {
            try Task.checkCancellation()

            let (data, response) = try await transport.data(for: request)
            try checkResponse(response, isAuthenticated: true)

            let httpResponse = response as! HTTPURLResponse
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            if contentType.hasPrefix("application/zip") {
                return JobResult(zipData: data, status: "completed")
            }

            let statusResponse = try decode(JobStatusResponse.self, from: data)
            let status = statusResponse.status

            if status == "completed" {
                return JobResult(zipData: nil, status: "completed")
            } else if status.hasPrefix("error:") {
                let message = String(status.dropFirst("error:".count))
                throw APIError.processingFailed(message)
            }

            // Estado intermedio: queued, separating, transcribing, etc.
            if intervalSeconds > 0 {
                try await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            }
        }

        throw APIError.timeout
    }

    /// GET /usage — consulta de uso mensual
    func getUsage(token: String) async throws -> UsageResponse {
        let endpoint = APIEndpoint.usage
        let request = makeRequest(endpoint: endpoint, token: token)

        let (data, response) = try await transport.data(for: request)
        try checkResponse(response, isAuthenticated: true)

        return try decode(UsageResponse.self, from: data)
    }

    // MARK: - Private Helpers

    private func makeRequest(endpoint: APIEndpoint, token: String?) -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func checkResponse(_ response: URLResponse, isAuthenticated: Bool) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let code = httpResponse.statusCode
        if code == 401 {
            throw isAuthenticated ? APIError.unauthorized : APIError.httpError(401)
        }
        guard (200..<300).contains(code) else {
            throw APIError.httpError(code)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
}
