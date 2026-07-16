import Combine
import Foundation

@MainActor
final class ToolExecution: ObservableObject, Identifiable {
    enum State: Equatable {
        case running
        case succeeded
        case failed
        case cancelled
    }

    let id: String
    let name: String
    let summary: String
    let input: String

    @Published private(set) var output = ""
    @Published private(set) var details = ""
    @Published private(set) var state = State.running

    init(id: String, name: String, arguments: Any) {
        self.id = id
        self.name = name
        summary = Self.summary(from: arguments)
        input = Self.json(arguments)
    }

    func update(with partialResult: Any?) {
        guard state == .running else { return }
        apply(partialResult)
    }

    func finish(with result: Any?, isError: Bool) {
        guard state == .running else { return }
        apply(result)
        state = isError ? .failed : .succeeded
    }

    func cancel() {
        guard state == .running else { return }
        state = .cancelled
    }

    private func apply(_ value: Any?) {
        guard let value, !(value is NSNull) else { return }
        guard let result = value as? [String: Any] else {
            output = Self.json(value)
            return
        }

        if let content = result["content"] as? [[String: Any]] {
            output = content.compactMap { block in
                switch block["type"] as? String {
                case "text":
                    return block["text"] as? String
                case "image":
                    return "[image]"
                case let type?:
                    return "[\(type)]"
                case nil:
                    return nil
                }
            }.joined(separator: "\n")
        }

        if let value = result["details"], !(value is NSNull) {
            let rendered = Self.details(value)
            details = rendered == "{}" ? "" : rendered
        }
    }

    private static func summary(from arguments: Any) -> String {
        guard let arguments = arguments as? [String: Any] else { return "" }
        for key in ["command", "pattern", "query", "path", "url"] {
            guard let value = arguments[key] as? String else { continue }
            let line = value.replacingOccurrences(of: "\n", with: " ")
            return line.count > 96 ? "\(line.prefix(95))…" : line
        }
        return ""
    }

    private static func details(_ value: Any) -> String {
        if
            let details = value as? [String: Any],
            let diff = details["diff"] as? String
        {
            return diff
        }
        return json(value)
    }

    private static func json(_ value: Any) -> String {
        guard
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(
                withJSONObject: value,
                options: [.prettyPrinted, .sortedKeys]
            ),
            let string = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return string
    }
}
