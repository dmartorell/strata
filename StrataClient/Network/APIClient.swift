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
    let result: JobResult?
}

struct JobResult: Decodable {
    // Placeholder para Phase 6 — estructura completa de stems, lyrics, chords
    // Se expande cuando el servidor devuelva datos reales de pipeline
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

// MARK: - APIClient

struct APIClient: Sendable {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    // Convenience initializer with URLSession (for backwards compatibility)
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

    /// POST /auth/renew — renovar JWT (endpoint a implementar en servidor en 03-02)
    func renewToken(current: String) async throws -> String {
        let endpoint = APIEndpoint.renew
        let request = makeRequest(endpoint: endpoint, token: current)

        let (data, response) = try await transport.data(for: request)
        try checkResponse(response, isAuthenticated: true)

        let decoded = try decode(LoginResponse.self, from: data)
        return decoded.token
    }

    /// POST /process — upload multipart de audio, devuelve job_id
    func uploadAudio(fileData: Data, fileName: String, mimeType: String, token: String) async throws -> String {
        let endpoint = APIEndpoint.process
        var multipart = MultipartRequest()
        multipart.addFile(name: "file", fileName: fileName, mimeType: mimeType, data: fileData)
        let body = multipart.finalize()

        var request = makeRequest(endpoint: endpoint, token: token)
        request.setValue(multipart.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

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

            let statusResponse = try decode(JobStatusResponse.self, from: data)
            let status = statusResponse.status

            if status == "completed" {
                return statusResponse.result ?? JobResult()
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

    /// Construye URLRequest inyectando Authorization: Bearer si token != nil
    private func makeRequest(endpoint: APIEndpoint, token: String?) -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = endpoint.method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Extrae HTTPURLResponse, lanza .unauthorized en 401, .httpError(code) en otros no-2xx
    private func checkResponse(_ response: URLResponse, isAuthenticated: Bool) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        let code = httpResponse.statusCode
        if code == 401 {
            // En requests autenticadas: lanza .unauthorized
            // En login (no autenticada): lanza .httpError(401) para señalar credenciales inválidas
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
