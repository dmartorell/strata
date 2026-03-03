import Testing
import Foundation
@testable import StrataClient

// MARK: - URLProtocol Mock

final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Helpers

func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: config)
}

func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

// MARK: - Login Tests

@Test("login devuelve JWT del campo 'token' con contraseña correcta")
func testLoginSuccess() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        let body = ["token": "jwt.token.here", "expires_in": 7776000] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (makeResponse(url: url, statusCode: 200), data)
    }

    let token = try await client.login(password: "correct")
    #expect(token == "jwt.token.here")
}

@Test("login con contraseña incorrecta lanza httpError(401)")
func testLoginUnauthorized() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        let data = try JSONSerialization.data(withJSONObject: ["detail": "Unauthorized"])
        return (makeResponse(url: url, statusCode: 401), data)
    }

    await #expect(throws: APIError.httpError(401)) {
        _ = try await client.login(password: "wrong")
    }
}

@Test("login envía POST con body JSON {password}")
func testLoginRequestFormat() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)
    var capturedRequest: URLRequest?

    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        let url = request.url!
        let data = try JSONSerialization.data(withJSONObject: ["token": "jwt", "expires_in": 7776000])
        return (makeResponse(url: url, statusCode: 200), data)
    }

    _ = try await client.login(password: "secret")

    let req = try #require(capturedRequest)
    #expect(req.httpMethod == "POST")
    #expect(req.url?.path == "/auth/login")

    let bodyData = try #require(req.httpBody)
    let body = try JSONSerialization.jsonObject(with: bodyData) as? [String: String]
    #expect(body?["password"] == "secret")
}

// MARK: - uploadAudio Tests

@Test("uploadAudio devuelve job_id con token válido")
func testUploadAudioSuccess() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        let data = try JSONSerialization.data(withJSONObject: ["job_id": "job-123"])
        return (makeResponse(url: url, statusCode: 200), data)
    }

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
    let session = makeMockSession()
    let client = APIClient(session: session)
    var capturedRequest: URLRequest?

    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        let url = request.url!
        let data = try JSONSerialization.data(withJSONObject: ["job_id": "job-456"])
        return (makeResponse(url: url, statusCode: 200), data)
    }

    _ = try await client.uploadAudio(
        fileData: Data("audio".utf8),
        fileName: "song.mp3",
        mimeType: "audio/mpeg",
        token: "my.jwt.token"
    )

    let req = try #require(capturedRequest)
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer my.jwt.token")
}

@Test("uploadAudio con token inválido lanza unauthorized")
func testUploadAudioUnauthorized() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        return (makeResponse(url: url, statusCode: 401), Data())
    }

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
    let session = makeMockSession()
    let client = APIClient(session: session)
    var callCount = 0

    MockURLProtocol.requestHandler = { request in
        callCount += 1
        let url = request.url!
        let status = callCount < 2 ? "separating" : "completed"
        let body: [String: Any] = ["status": status, "result": ["stems": [], "lyrics": [], "chords": []]]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (makeResponse(url: url, statusCode: 200), data)
    }

    let result = try await client.pollJobStatus(jobId: "job-123", token: "valid.token", intervalSeconds: 0)
    #expect(callCount == 2)
    _ = result // JobResult devuelto correctamente
}

@Test("pollJobStatus lanza processingFailed cuando status empieza por 'error:'")
func testPollJobStatusError() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        let body: [String: Any] = ["status": "error:stems_failed", "result": NSNull()]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (makeResponse(url: url, statusCode: 200), data)
    }

    await #expect(throws: APIError.processingFailed("stems_failed")) {
        _ = try await client.pollJobStatus(jobId: "job-err", token: "valid.token", intervalSeconds: 0)
    }
}

@Test("pollJobStatus lanza timeout tras maxAttempts intentos sin resultado")
func testPollJobStatusTimeout() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        let body: [String: Any] = ["status": "queued", "result": NSNull()]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (makeResponse(url: url, statusCode: 200), data)
    }

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
    let session = makeMockSession()
    let client = APIClient(session: session)
    var capturedRequest: URLRequest?

    MockURLProtocol.requestHandler = { request in
        capturedRequest = request
        let url = request.url!
        let body: [String: Any] = [
            "month": "2026-03",
            "songs_processed": 5,
            "gpu_seconds": 123.4,
            "estimated_cost_usd": 0.05
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (makeResponse(url: url, statusCode: 200), data)
    }

    let usage = try await client.getUsage(token: "valid.token")
    #expect(usage.month == "2026-03")
    #expect(usage.songs_processed == 5)
    #expect(usage.gpu_seconds == 123.4)
    #expect(usage.estimated_cost_usd == 0.05)

    let req = try #require(capturedRequest)
    #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer valid.token")
    #expect(req.url?.path == "/usage")
}

@Test("getUsage con token inválido lanza unauthorized")
func testGetUsageUnauthorized() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        return (makeResponse(url: url, statusCode: 401), Data())
    }

    await #expect(throws: APIError.unauthorized) {
        _ = try await client.getUsage(token: "expired.token")
    }
}

// MARK: - 401 propagation

@Test("cualquier 401 en request autenticada lanza unauthorized (no httpError(401))")
func testAny401LandsAsUnauthorized() async throws {
    let session = makeMockSession()
    let client = APIClient(session: session)

    MockURLProtocol.requestHandler = { request in
        let url = request.url!
        return (makeResponse(url: url, statusCode: 401), Data())
    }

    await #expect(throws: APIError.unauthorized) {
        _ = try await client.getUsage(token: "bad.token")
    }
}
