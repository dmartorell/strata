import Testing
import Foundation
@testable import SiyahambaClient

// MARK: - Mock Transport

/// Mock de HTTPTransport — permite configurar respuesta por URL/método sin URLProtocol
actor MockTransport: HTTPTransport {
    private var handlers: [(URLRequest) -> (Data, URLResponse)?] = []

    /// Añade una respuesta JSON para la próxima llamada (FIFO)
    func enqueue(statusCode: Int, body: Any, url: URL? = nil) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = HTTPURLResponse(url: url ?? URL(string: "https://mock.local")!,
                                       statusCode: statusCode,
                                       httpVersion: nil,
                                       headerFields: nil)!
        handlers.append { _ in (data, response) }
    }

    /// Añade una respuesta que captura el request para su inspección
    func enqueueCapturing(statusCode: Int, body: Any, into captured: inout URLRequest?) {
        // Captura se hace en el closure — no se puede mutar `captured` directamente con actor
        // Usar enqueue y capturar en el test via expectedRequest
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let response = HTTPURLResponse(url: URL(string: "https://mock.local")!,
                                       statusCode: statusCode,
                                       httpVersion: nil,
                                       headerFields: nil)!
        handlers.append { _ in (data, response) }
    }

    nonisolated func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        // Necesitamos ejecutar en el actor para acceder a los handlers
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                let result = await self.dequeueHandler(for: request)
                if let (data, response) = result {
                    continuation.resume(returning: (data, response))
                } else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                }
            }
        }
    }

    private func dequeueHandler(for request: URLRequest) -> (Data, URLResponse)? {
        guard !handlers.isEmpty else { return nil }
        let handler = handlers.removeFirst()
        return handler(request)
    }

    func capturedRequests() -> [URLRequest] { [] }
}

// MARK: - Simple Synchronous Mock (sin actor, para tests simples)

/// Mock síncrono que usa closures — más simple y predecible
final class SimpleMockTransport: HTTPTransport, @unchecked Sendable {
    var handler: ((URLRequest) async throws -> (Data, URLResponse))?
    private(set) var lastRequest: URLRequest?
    private var callCount = 0
    private var responses: [(statusCode: Int, body: Any)] = []
    private let lock = NSLock()

    func enqueue(statusCode: Int, body: Any) {
        lock.lock()
        defer { lock.unlock() }
        responses.append((statusCode: statusCode, body: body))
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.lock()
        lastRequest = request
        callCount += 1

        if let customHandler = handler {
            lock.unlock()
            return try await customHandler(request)
        }

        guard !responses.isEmpty else {
            lock.unlock()
            throw URLError(.badServerResponse)
        }

        let (statusCode, body) = responses.removeFirst()
        lock.unlock()

        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        let url = request.url ?? URL(string: "https://mock.local")!
        let response = HTTPURLResponse(url: url, statusCode: statusCode,
                                       httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    func getCallCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return callCount
    }
}

// MARK: - Login Tests

@Test("login devuelve JWT del campo 'token' con contraseña correcta")
func testLoginSuccess() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 200, body: ["token": "jwt.token.here", "expires_in": 7776000])
    let client = APIClient(transport: transport)

    let token = try await client.login(password: "correct")
    #expect(token == "jwt.token.here")
}

@Test("login con contraseña incorrecta lanza httpError(401)")
func testLoginUnauthorized() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 401, body: ["detail": "Unauthorized"])
    let client = APIClient(transport: transport)

    await #expect(throws: APIError.httpError(401)) {
        _ = try await client.login(password: "wrong")
    }
}

@Test("login envía POST con body JSON {password}")
func testLoginRequestFormat() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 200, body: ["token": "jwt", "expires_in": 7776000])
    let client = APIClient(transport: transport)

    _ = try await client.login(password: "secret")

    let req = try #require(transport.lastRequest)
    #expect(req.httpMethod == "POST")
    #expect(req.url?.path == "/auth/login")

    let bodyData = try #require(req.httpBody)
    let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: String]
    #expect(body?["password"] == "secret")
}

// MARK: - uploadAudio Tests

@Test("uploadAudio devuelve job_id con token válido")
func testUploadAudioSuccess() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 200, body: ["job_id": "job-123"])
    let client = APIClient(transport: transport)

    let jobId = try await client.uploadAudio(
        fileData: Data("fake audio".utf8),
        fileName: "test.mp3",
        mimeType: "audio/mpeg",
        token: "valid.jwt.token"
    )
    #expect(jobId == "job-123")
}

@Test("uploadAudio inyecta Authorization Bearer header")
func testUploadAudioAuthHeader() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 200, body: ["job_id": "job-456"])
    let client = APIClient(transport: transport)

    _ = try await client.uploadAudio(
        fileData: Data("audio".utf8),
        fileName: "song.mp3",
        mimeType: "audio/mpeg",
        token: "my.jwt.token"
    )

    let req = try #require(transport.lastRequest)
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer my.jwt.token")
}

@Test("uploadAudio con token inválido lanza unauthorized")
func testUploadAudioUnauthorized() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 401, body: [:])
    let client = APIClient(transport: transport)

    await #expect(throws: APIError.unauthorized) {
        _ = try await client.uploadAudio(
            fileData: Data("audio".utf8),
            fileName: "song.mp3",
            mimeType: "audio/mpeg",
            token: "invalid.token"
        )
    }
}

// MARK: - pollJobStatus Tests

@Test("pollJobStatus devuelve JobResult cuando status es completed")
func testPollJobStatusCompleted() async throws {
    let transport = SimpleMockTransport()
    // Primera llamada: en proceso
    transport.enqueue(statusCode: 200, body: ["status": "separating", "result": NSNull()])
    // Segunda llamada: completado
    transport.enqueue(statusCode: 200, body: ["status": "completed", "result": [:] as [String: Any]])
    let client = APIClient(transport: transport)

    let result = try await client.pollJobStatus(jobId: "job-123", token: "valid.token", intervalSeconds: 0)
    #expect(transport.getCallCount() == 2)
    _ = result // JobResult devuelto correctamente
}

@Test("pollJobStatus lanza processingFailed cuando status empieza por 'error:'")
func testPollJobStatusError() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 200, body: ["status": "error:stems_failed", "result": NSNull()])
    let client = APIClient(transport: transport)

    await #expect(throws: APIError.processingFailed("stems_failed")) {
        _ = try await client.pollJobStatus(jobId: "job-err", token: "valid.token", intervalSeconds: 0)
    }
}

@Test("pollJobStatus lanza timeout tras maxAttempts intentos sin resultado")
func testPollJobStatusTimeout() async throws {
    let transport = SimpleMockTransport()
    // Enqueue 3 respuestas de "queued"
    for _ in 0..<3 {
        transport.enqueue(statusCode: 200, body: ["status": "queued", "result": NSNull()])
    }
    let client = APIClient(transport: transport)

    await #expect(throws: APIError.timeout) {
        _ = try await client.pollJobStatus(
            jobId: "job-stuck",
            token: "valid.token",
            intervalSeconds: 0,
            maxAttempts: 3
        )
    }
}

// MARK: - getUsage Tests

@Test("getUsage devuelve UsageResponse con Authorization Bearer")
func testGetUsageSuccess() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 200, body: [
        "month": "2026-03",
        "songs_processed": 5,
        "gpu_seconds": 123.4,
        "estimated_cost_usd": 0.05
    ])
    let client = APIClient(transport: transport)

    let usage = try await client.getUsage(token: "valid.token")
    #expect(usage.month == "2026-03")
    #expect(usage.songs_processed == 5)
    #expect(usage.gpu_seconds == 123.4)
    #expect(usage.estimated_cost_usd == 0.05)

    let req = try #require(transport.lastRequest)
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer valid.token")
    #expect(req.url?.path == "/usage")
}

@Test("getUsage con token inválido lanza unauthorized")
func testGetUsageUnauthorized() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 401, body: [:])
    let client = APIClient(transport: transport)

    await #expect(throws: APIError.unauthorized) {
        _ = try await client.getUsage(token: "expired.token")
    }
}

// MARK: - 401 propagation

@Test("cualquier 401 en request autenticada lanza unauthorized (no httpError(401))")
func testAny401LandsAsUnauthorized() async throws {
    let transport = SimpleMockTransport()
    transport.enqueue(statusCode: 401, body: [:])
    let client = APIClient(transport: transport)

    await #expect(throws: APIError.unauthorized) {
        _ = try await client.getUsage(token: "bad.token")
    }
}
