import Combine
import Darwin
import Foundation

struct ConversationMessage: Identifiable {
    enum Role {
        case user
        case assistant
        case thinking
        case error
        case toolCall(ToolExecution)
    }

    let id = UUID()
    let role: Role
    var text: String
}

@MainActor
final class PiSession: ObservableObject {
    @Published private(set) var messages: [ConversationMessage] = []
    @Published private(set) var isRunning = false
    @Published private(set) var isAvailable = false
    @Published var draft = ""

    private let workingDirectory: URL
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private var assistantMessageID: UUID?
    private var thinkingMessageID: UUID?
    private var runningTools: [String: ToolExecution] = [:]
    private var stopTask: Task<Void, Never>?
    private var isStopping = false
    private var requestID = 0

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
        start()
    }

    var hasUserMessages: Bool {
        messages.contains { message in
            if case .user = message.role { return true }
            return false
        }
    }

    func prompt(_ message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let wasRunning = isRunning
        messages.append(ConversationMessage(role: .user, text: message))
        isRunning = true

        var command: [String: Any] = [
            "id": nextRequestID(),
            "type": "prompt",
            "message": message,
        ]
        if wasRunning {
            command["streamingBehavior"] = "steer"
        }

        if !send(command) {
            isRunning = false
        }
    }

    func setName(_ name: String) {
        send(["type": "set_session_name", "name": name])
    }

    func abort() {
        guard isRunning else { return }
        send(["type": "abort"])
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        isAvailable = false
        isRunning = false
        cancelRunningTools()
        try? input?.fileHandleForWriting.close()

        guard let process, process.isRunning else { return }
        stopTask = Task { [process] in
            try? await Task.sleep(for: .seconds(1))
            guard process.isRunning else { return }
            process.terminate()

            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func start() {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        var environment = ProcessInfo.processInfo.environment

        if let executable = environment["PI_EXECUTABLE"], !executable.isEmpty {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["--mode", "rpc"]
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["pi", "--mode", "rpc"]
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let commonPaths = [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "\(home)/.local/bin",
                "\(home)/.local/share/pi-node/current/bin",
                "\(home)/.npm-global/bin",
                "/usr/bin",
                "/bin",
            ]
            let inheritedPaths = environment["PATH"]?
                .split(separator: ":")
                .map(String.init)
                .filter { $0.hasPrefix("/") } ?? []
            environment["PATH"] = (commonPaths + inheritedPaths).joined(separator: ":")
        }

        environment["PI_SKIP_VERSION_CHECK"] = "1"
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeOutput(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeErrors(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.didTerminate(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
            self.process = process
            self.input = input
            self.output = output
            self.errors = errors
            isAvailable = true
        } catch {
            appendError("Could not start Pi: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func send(_ command: [String: Any]) -> Bool {
        guard isAvailable, let handle = input?.fileHandleForWriting else {
            appendError("Pi is not available. Install Pi or set PI_EXECUTABLE.")
            return false
        }

        do {
            var data = try JSONSerialization.data(withJSONObject: command)
            data.append(0x0A)
            try handle.write(contentsOf: data)
            return true
        } catch {
            appendError("Could not send message to Pi: \(error.localizedDescription)")
            return false
        }
    }

    private func nextRequestID() -> String {
        requestID += 1
        return String(requestID)
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        for line in completeLines(in: &outputBuffer) {
            handle(line)
        }
    }

    private func consumeErrors(_ data: Data) {
        errorBuffer.append(data)
        for line in completeLines(in: &errorBuffer) {
            guard let text = String(data: line, encoding: .utf8), !text.isEmpty else { continue }
            appendError(text)
        }
    }

    private func completeLines(in buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if line.last == 0x0D {
                line.removeLast()
            }
            lines.append(line)
        }
        return lines
    }

    private func handle(_ data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let event = object as? [String: Any],
            let type = event["type"] as? String
        else {
            appendError("Pi returned an invalid response.")
            return
        }

        switch type {
        case "agent_start":
            isRunning = true

        case "agent_settled":
            isRunning = false
            assistantMessageID = nil
            thinkingMessageID = nil

        case "message_start":
            if let message = event["message"] as? [String: Any], message["role"] as? String == "assistant" {
                assistantMessageID = nil
                thinkingMessageID = nil
            }

        case "message_update":
            guard let update = event["assistantMessageEvent"] as? [String: Any] else { return }
            switch update["type"] as? String {
            case "text_delta":
                if let delta = update["delta"] as? String {
                    appendAssistant(delta)
                }
            case "thinking_delta":
                if let delta = update["delta"] as? String {
                    appendThinking(delta)
                }
            default:
                break
            }

        case "message_end":
            guard let message = event["message"] as? [String: Any], message["role"] as? String == "assistant" else { return }
            if let error = message["errorMessage"] as? String, !error.isEmpty {
                appendError(error)
            }
            assistantMessageID = nil
            thinkingMessageID = nil

        case "tool_execution_start":
            startTool(event)

        case "tool_execution_update":
            updateTool(event)

        case "tool_execution_end":
            finishTool(event)

        case "response":
            if event["success"] as? Bool == false {
                appendError(event["error"] as? String ?? "Pi rejected the command.")
                if event["command"] as? String == "prompt" {
                    isRunning = false
                }
            }

        case "extension_ui_request":
            guard
                let method = event["method"] as? String,
                ["select", "confirm", "input", "editor"].contains(method),
                let id = event["id"] as? String
            else { return }
            send(["type": "extension_ui_response", "id": id, "cancelled": true])

        default:
            break
        }
    }

    private func startTool(_ event: [String: Any]) {
        guard
            let id = event["toolCallId"] as? String,
            let name = event["toolName"] as? String,
            runningTools[id] == nil
        else { return }

        let execution = ToolExecution(
            id: id,
            name: name,
            arguments: event["args"] ?? [:]
        )
        runningTools[id] = execution
        messages.append(ConversationMessage(role: .toolCall(execution), text: ""))
    }

    private func updateTool(_ event: [String: Any]) {
        guard
            let id = event["toolCallId"] as? String,
            let execution = runningTools[id]
        else { return }
        execution.update(with: event["partialResult"])
    }

    private func finishTool(_ event: [String: Any]) {
        guard
            let id = event["toolCallId"] as? String,
            let execution = runningTools.removeValue(forKey: id)
        else { return }
        execution.finish(
            with: event["result"],
            isError: event["isError"] as? Bool ?? false
        )
    }

    private func cancelRunningTools() {
        for execution in runningTools.values {
            execution.cancel()
        }
        runningTools.removeAll()
    }

    private func appendAssistant(_ delta: String) {
        if assistantMessageID == nil {
            let message = ConversationMessage(role: .assistant, text: "")
            assistantMessageID = message.id
            messages.append(message)
        }
        guard let id = assistantMessageID, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += delta
    }

    private func appendThinking(_ delta: String) {
        if thinkingMessageID == nil {
            let message = ConversationMessage(role: .thinking, text: "")
            thinkingMessageID = message.id
            messages.append(message)
        }
        guard let id = thinkingMessageID, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += delta
    }

    private func appendError(_ text: String) {
        messages.append(ConversationMessage(role: .error, text: text))
    }

    private func didTerminate(status: Int32) {
        let stoppedIntentionally = isStopping
        stopTask?.cancel()
        stopTask = nil
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        process = nil
        input = nil
        output = nil
        errors = nil
        isAvailable = false
        isRunning = false
        cancelRunningTools()

        guard !stoppedIntentionally else { return }
        appendError(status == 0 ? "Pi stopped unexpectedly." : "Pi exited with status \(status).")
    }
}
