import Bonsplit
import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        BonsplitView(controller: appState.controller) { tab, pane in
            let isActive = appState.controller.selectedTab(inPane: pane)?.id == tab.id
                && appState.controller.focusedPaneId == pane

            Group {
                if let session = appState.sessions[tab.id] {
                    SessionView(
                        session: session,
                        isActive: isActive,
                        onSubmit: { message in
                            appState.prompt(message, in: tab.id)
                        },
                        onFocus: {
                            appState.controller.focusPane(pane)
                        },
                        onOpenToolCall: { execution in
                            appState.openToolCall(execution, from: pane)
                        }
                    )
                } else if let execution = appState.toolCallTabs[tab.id] {
                    ToolExecutionView(execution: execution)
                }
            }
            .animation(nil, value: tab.id)
        } emptyPane: { pane in
            Button("New Session") {
                appState.newSession(inPane: pane)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .focusedSceneObject(appState)
        .frame(minWidth: 480, minHeight: 320)
        .onDisappear {
            appState.stopAllSessions()
        }
    }
}

private struct SessionView: View {
    @ObservedObject var session: PiSession
    let isActive: Bool
    let onSubmit: (String) -> Void
    let onFocus: () -> Void
    let onOpenToolCall: (ToolExecution) -> Void

    @FocusState private var inputIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            transcript
            Divider()
            inputField
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: inputIsFocused) { _, focused in
            if focused {
                onFocus()
            }
        }
        .onAppear {
            inputIsFocused = isActive
        }
        .onChange(of: isActive) { _, active in
            inputIsFocused = active
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.messages) { message in
                        Group {
                            switch message.role {
                            case .toolCall(let execution):
                                ToolCallRow(execution: execution) {
                                    onOpenToolCall(execution)
                                }
                            case .user, .assistant, .thinking, .error:
                                MessageRow(message: message)
                            }
                        }
                        .id(message.id)
                    }
                }
                .padding(16)
            }
            .onAppear {
                scrollToBottom(proxy)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: session.messages.last?.text) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private var inputField: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(
                session.isAvailable ? "Message Pi" : "Pi is unavailable",
                text: $session.draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1...8)
            .focused($inputIsFocused)
            .disabled(!session.isAvailable)
            .onSubmit(submit)

            if session.isRunning {
                Button {
                    session.abort()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Stop")
            }
        }
        .padding(12)
    }

    private func submit() {
        let message = session.draft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        session.draft = ""
        onSubmit(message)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let id = session.messages.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }
}

private struct MessageRow: View {
    let message: ConversationMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(labelColor)
            Text(message.text)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var label: String {
        switch message.role {
        case .user: "YOU"
        case .assistant: "PI"
        case .thinking: "THINKING"
        case .error: "ERROR"
        case .toolCall: "TOOL"
        }
    }

    private var labelColor: Color {
        switch message.role {
        case .user, .thinking: .secondary
        case .assistant: .accentColor
        case .error: .red
        case .toolCall: .secondary
        }
    }

    private var textColor: Color {
        switch message.role {
        case .thinking: .secondary
        case .error: .red
        default: .primary
        }
    }
}

private struct ToolCallRow: View {
    @ObservedObject var execution: ToolExecution
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Image(systemName: stateIcon)
                    .frame(width: 12)
                    .foregroundStyle(stateColor)
                Text(execution.name)
                    .foregroundStyle(.primary)
                if !execution.summary.isEmpty {
                    Text(execution.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(.callout, design: .monospaced))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open tool call in a new tab")
        .accessibilityLabel("Open \(execution.name) tool call")
        .accessibilityValue(stateLabel)
    }

    private var stateLabel: String {
        switch execution.state {
        case .running: "Running"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private var stateIcon: String {
        switch execution.state {
        case .running: "ellipsis"
        case .succeeded: "checkmark"
        case .failed: "xmark"
        case .cancelled: "minus"
        }
    }

    private var stateColor: Color {
        switch execution.state {
        case .running: .secondary
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
        }
    }
}

private struct ToolExecutionView: View {
    @ObservedObject var execution: ToolExecution

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text(execution.name)
                        .font(.headline.monospaced())
                    Spacer()
                    Text(status)
                        .font(.caption.monospaced())
                        .foregroundStyle(statusColor)
                }

                section("INPUT", execution.input)
                if !execution.output.isEmpty {
                    section("OUTPUT", execution.output)
                }
                if !execution.details.isEmpty {
                    section("DETAILS", execution.details)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var status: String {
        switch execution.state {
        case .running: "RUNNING"
        case .succeeded: "DONE"
        case .failed: "FAILED"
        case .cancelled: "CANCELLED"
        }
    }

    private var statusColor: Color {
        switch execution.state {
        case .running, .cancelled: .secondary
        case .succeeded: .green
        case .failed: .red
        }
    }
}
