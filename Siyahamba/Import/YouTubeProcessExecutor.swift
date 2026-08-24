import Foundation

struct YouTubeProcessResult: Sendable {
    let status: Int32
    let standardOutput: Data
    let standardError: Data
}

protocol YouTubeProcessExecuting: Sendable {
    func run(executable: URL, arguments: [String]) async throws -> YouTubeProcessResult
    func run(executable: URL, arguments: [String], onOutput: @escaping @Sendable (String) -> Void) async throws -> YouTubeProcessResult
}

extension YouTubeProcessExecuting {
    func run(executable: URL, arguments: [String], onOutput: @escaping @Sendable (String) -> Void) async throws -> YouTubeProcessResult {
        let result = try await run(executable: executable, arguments: arguments)
        onOutput(String(decoding: result.standardError, as: UTF8.self))
        return result
    }
}

private actor ActiveProcess {
    private var process: Process?

    func set(_ process: Process) { self.process = process }
    func terminate() { process?.terminate() }
}

enum YouTubeProcessExecutorError: LocalizedError {
    case couldNotStart(String)

    var errorDescription: String? {
        switch self {
        case .couldNotStart(let name): "No se pudo iniciar \(name)."
        }
    }
}

struct YouTubeProcessExecutor: YouTubeProcessExecuting {
    func run(executable: URL, arguments: [String]) async throws -> YouTubeProcessResult {
        try await run(executable: executable, arguments: arguments, onOutput: { _ in })
    }

    func run(
        executable: URL,
        arguments: [String],
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> YouTubeProcessResult {
        let activeProcess = ActiveProcess()
        let result = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                let output = Pipe()
                let error = Pipe()
                var standardOutput = Data()
                var standardError = Data()
                let lock = NSLock()

                output.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    lock.lock()
                    standardOutput.append(data)
                    lock.unlock()
                }
                error.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    lock.lock()
                    standardError.append(data)
                    lock.unlock()
                    onOutput(String(decoding: data, as: UTF8.self))
                }

                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = output
                process.standardError = error
                process.terminationHandler = { finished in
                    output.fileHandleForReading.readabilityHandler = nil
                    error.fileHandleForReading.readabilityHandler = nil
                    lock.lock()
                    standardOutput.append(output.fileHandleForReading.readDataToEndOfFile())
                    standardError.append(error.fileHandleForReading.readDataToEndOfFile())
                    let result = YouTubeProcessResult(status: finished.terminationStatus, standardOutput: standardOutput, standardError: standardError)
                    lock.unlock()
                    continuation.resume(returning: result)
                }
                do {
                    try process.run()
                    Task { await activeProcess.set(process) }
                } catch {
                    continuation.resume(throwing: YouTubeProcessExecutorError.couldNotStart(executable.lastPathComponent))
                }
            }
        }, onCancel: {
            Task { await activeProcess.terminate() }
        })
        try Task.checkCancellation()
        return result
    }
}
