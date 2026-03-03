import Foundation

enum APIEndpoint {
    // La baseURL se puede sobreescribir con la variable de entorno STRATA_API_URL (útil en tests)
    static var baseURL: URL = {
        if let envURL = ProcessInfo.processInfo.environment["STRATA_API_URL"],
           let url = URL(string: envURL) {
            return url
        }
        return URL(string: "https://dani-martorell--strata-web.modal.run")!
    }()

    case login
    case renew
    case processFile
    case processURL
    case result(jobId: String)
    case usage

    var url: URL {
        switch self {
        case .login:
            return APIEndpoint.baseURL.appendingPathComponent("auth/login")
        case .renew:
            return APIEndpoint.baseURL.appendingPathComponent("auth/renew")
        case .processFile:
            return APIEndpoint.baseURL.appendingPathComponent("process-file")
        case .processURL:
            return APIEndpoint.baseURL.appendingPathComponent("process-url")
        case .result(let jobId):
            return APIEndpoint.baseURL.appendingPathComponent("result/\(jobId)")
        case .usage:
            return APIEndpoint.baseURL.appendingPathComponent("usage")
        }
    }

    var method: String {
        switch self {
        case .login, .renew, .processFile, .processURL:
            return "POST"
        case .result, .usage:
            return "GET"
        }
    }
}
