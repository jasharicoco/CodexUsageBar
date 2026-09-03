import Foundation

public enum CodexUsageClientError: LocalizedError, Equatable {
    case executableNotFound
    case notLoggedIn
    case chatGPTAccountRequired
    case unsupportedAccount
    case launchFailed(String)
    case connectionClosed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return CoreStrings.text(
                swedish: "Codex hittades inte. Installera Codex-appen eller Codex CLI och logga in.",
                english: "Codex was not found. Install the Codex app or Codex CLI and sign in."
            )
        case .notLoggedIn:
            return CoreStrings.text(
                swedish: "Codex är installerat, men inget konto är inloggat.",
                english: "Codex is installed, but no account is signed in."
            )
        case .chatGPTAccountRequired:
            return CoreStrings.text(
                swedish: "Codex använder en API-nyckel. Veckogränsen är bara tillgänglig med ChatGPT-inloggning.",
                english: "Codex is using an API key. The weekly limit is only available with ChatGPT sign-in."
            )
        case .unsupportedAccount:
            return CoreStrings.text(
                swedish: "Det aktiva Codex-kontot har ingen kompatibel veckogräns.",
                english: "The active Codex account does not provide a compatible weekly limit."
            )
        case .launchFailed(let message):
            return CoreStrings.text(
                swedish: "Codex kunde inte startas: \(message)",
                english: "Codex could not be started: \(message)"
            )
        case .connectionClosed(let details):
            if details.isEmpty {
                return CoreStrings.text(
                    swedish: "Anslutningen till Codex stängdes innan användningen kunde läsas.",
                    english: "The Codex connection closed before usage could be read."
                )
            }
            return CoreStrings.text(
                swedish: "Codex stängde anslutningen: \(details)",
                english: "Codex closed the connection: \(details)"
            )
        case .timedOut:
            return CoreStrings.text(
                swedish: "Codex tog för lång tid på sig att svara.",
                english: "Codex took too long to respond."
            )
        }
    }
}

public final class CodexUsageClient {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let response = try await perform(.readUsage)
        guard case .usage(let snapshot) = response else {
            throw UsageParsingError.invalidResponse
        }
        return snapshot
    }

    public func consumeReset(
        creditId: String?,
        idempotencyKey: UUID = UUID()
    ) async throws -> UsageResetOutcome {
        let response = try await perform(
            .consumeReset(
                creditId: creditId,
                idempotencyKey: idempotencyKey.uuidString
            )
        )
        guard case .reset(let outcome) = response else {
            throw UsageResetParsingError.invalidResponse
        }
        return outcome
    }

    private func perform(_ operation: AppServerOperation) async throws -> AppServerResponse {
        guard let executableURL = CodexExecutable.locate() else {
            throw CodexUsageClientError.executableNotFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            AppServerRequest(
                executableURL: executableURL,
                operation: operation,
                continuation: continuation
            ).start()
        }
    }
}

private enum AppServerOperation {
    case readUsage
    case consumeReset(creditId: String?, idempotencyKey: String)
}

private enum AppServerResponse {
    case usage(UsageSnapshot)
    case reset(UsageResetOutcome)
}

private enum CodexExecutable {
    static func locate() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let override = environment["CODEX_PATH"], !override.isEmpty {
            candidates.append(override)
        }

        candidates.append("/Applications/ChatGPT.app/Contents/Resources/codex")
        candidates.append("/Applications/Codex.app/Contents/Resources/codex")

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append("\(home)/.local/bin/codex")
        candidates.append("\(home)/bin/codex")
        candidates.append("/opt/homebrew/bin/codex")
        candidates.append("/usr/local/bin/codex")

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/codex" })
        }

        return candidates
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}

private final class AppServerRequest {
    private let executableURL: URL
    private let operation: AppServerOperation
    private let continuation: CheckedContinuation<AppServerResponse, Error>
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errorOutput = Pipe()
    private let queue = DispatchQueue(label: "se.codexusagebar.app-server")

    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var didFinish = false
    private var keepAlive: AppServerRequest?
    private var timeout: DispatchWorkItem?

    init(
        executableURL: URL,
        operation: AppServerOperation,
        continuation: CheckedContinuation<AppServerResponse, Error>
    ) {
        self.executableURL = executableURL
        self.operation = operation
        self.continuation = continuation
    }

    func start() {
        keepAlive = self

        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.receive(data)
            }
        }

        errorOutput.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.errorBuffer.append(data)
            }
        }

        process.terminationHandler = { [weak self] process in
            self?.queue.async {
                guard let self, !self.didFinish else { return }
                let details = String(data: self.errorBuffer, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.finish(.failure(CodexUsageClientError.connectionClosed(details)))
            }
        }

        do {
            try process.run()
        } catch {
            finish(.failure(CodexUsageClientError.launchFailed(error.localizedDescription)))
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            self?.finish(.failure(CodexUsageClientError.timedOut))
        }
        self.timeout = timeout
        queue.asyncAfter(deadline: .now() + 20, execute: timeout)

        send(
            "{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"codex-usage-bar\",\"title\":\"Codex Usage Bar\",\"version\":\"1.0.0\"},\"capabilities\":{\"experimentalApi\":true}}}"
        )
    }

    private func receive(_ data: Data) {
        guard !didFinish else { return }
        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            handleLine(Data(line))
        }
    }

    private func handleLine(_ data: Data) {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let identifier = (payload["id"] as? NSNumber)?.intValue
        else {
            return
        }

        switch identifier {
        case 1:
            if let error = payload["error"] as? [String: Any] {
                let message = error["message"] as? String ?? CoreStrings.text(
                    swedish: "Initiering misslyckades.",
                    english: "Initialization failed."
                )
                finish(.failure(UsageParsingError.server(message)))
                return
            }

            send("{\"method\":\"initialized\"}")
            send("{\"id\":2,\"method\":\"account/read\",\"params\":{\"refreshToken\":false}}")

        case 2:
            handleAccountResponse(data)

        case 3:
            do {
                switch operation {
                case .readUsage:
                    let snapshot = try UsageResponseParser.parse(data)
                    finish(.success(.usage(snapshot)))
                case .consumeReset:
                    let outcome = try UsageResponseParser.parseResetOutcome(data)
                    finish(.success(.reset(outcome)))
                }
            } catch {
                finish(.failure(error))
            }

        default:
            break
        }
    }

    private func handleAccountResponse(_ data: Data) {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            finish(.failure(UsageParsingError.invalidResponse))
            return
        }

        if let error = payload["error"] as? [String: Any] {
            let message = error["message"] as? String ?? CoreStrings.text(
                swedish: "Kontot kunde inte läsas.",
                english: "The account could not be read."
            )
            finish(.failure(UsageParsingError.server(message)))
            return
        }

        guard let result = payload["result"] as? [String: Any] else {
            finish(.failure(UsageParsingError.invalidResponse))
            return
        }

        guard
            let account = result["account"] as? [String: Any],
            let accountType = account["type"] as? String
        else {
            finish(.failure(CodexUsageClientError.notLoggedIn))
            return
        }

        switch accountType {
        case "chatgpt":
            switch operation {
            case .readUsage:
                send("{\"id\":3,\"method\":\"account/rateLimits/read\",\"params\":null}")
            case .consumeReset(let creditId, let idempotencyKey):
                var parameters = ["idempotencyKey": idempotencyKey]
                if let creditId, !creditId.isEmpty {
                    parameters["creditId"] = creditId
                }
                send(
                    jsonObject: [
                        "id": 3,
                        "method": "account/rateLimitResetCredit/consume",
                        "params": parameters
                    ]
                )
            }
        case "apiKey":
            finish(.failure(CodexUsageClientError.chatGPTAccountRequired))
        default:
            finish(.failure(CodexUsageClientError.unsupportedAccount))
        }
    }

    private func send(_ line: String) {
        guard !didFinish, let data = "\(line)\n".data(using: .utf8) else { return }

        do {
            try input.fileHandleForWriting.write(contentsOf: data)
        } catch {
            finish(.failure(CodexUsageClientError.connectionClosed(error.localizedDescription)))
        }
    }

    private func send(jsonObject: [String: Any]) {
        guard
            JSONSerialization.isValidJSONObject(jsonObject),
            let data = try? JSONSerialization.data(withJSONObject: jsonObject),
            let line = String(data: data, encoding: .utf8)
        else {
            finish(.failure(UsageResetParsingError.invalidResponse))
            return
        }

        send(line)
    }

    private func finish(_ result: Result<AppServerResponse, Error>) {
        guard !didFinish else { return }
        didFinish = true
        timeout?.cancel()

        output.fileHandleForReading.readabilityHandler = nil
        errorOutput.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? input.fileHandleForWriting.close()

        if process.isRunning {
            process.terminate()
        }

        continuation.resume(with: result)
        keepAlive = nil
    }
}
