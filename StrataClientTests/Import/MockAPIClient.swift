import Foundation
@testable import StrataClient

// MARK: - MockAuthTokenProvider

final class MockAuthTokenProvider: AuthTokenProviderProtocol, @unchecked Sendable {
    var token: String?

    init(token: String? = "test-token-123") {
        self.token = token
    }
}

actor MockImportAPIClient: ImportAPIClientProtocol {
    var uploadAudioResult: Result<String, Error> = .success("job-123")
    var uploadURLResult: Result<String, Error> = .success("job-456")
    var pollResult: Result<JobResult, Error> = .success(JobResult(zipData: nil, status: "completed"))

    var uploadAudioCallCount = 0
    var uploadURLCallCount = 0
    var pollCallCount = 0

    func setUploadAudioResult(_ result: Result<String, Error>) {
        uploadAudioResult = result
    }

    func setUploadURLResult(_ result: Result<String, Error>) {
        uploadURLResult = result
    }

    func setPollResult(_ result: Result<JobResult, Error>) {
        pollResult = result
    }

    func uploadAudio(fileData: Data, fileName: String, mimeType: String, token: String) async throws -> String {
        uploadAudioCallCount += 1
        return try uploadAudioResult.get()
    }

    func uploadURL(urlString: String, token: String) async throws -> String {
        uploadURLCallCount += 1
        return try uploadURLResult.get()
    }

    func pollJobStatus(jobId: String, token: String, intervalSeconds: Double, maxAttempts: Int) async throws -> JobResult {
        pollCallCount += 1
        return try pollResult.get()
    }
}
