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
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(Color.accentColor)
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
            inputField
        }
        .background(Color(nsColor: .windowBackgroundColor))
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
                LazyVStack(alignment: .leading, spacing: 22) {
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
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
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
            .font(.body)
            .lineLimit(1...8)
            .focused($inputIsFocused)
            .disabled(!session.isAvailable)
            .onSubmit(submit)

            if session.isRunning {
                Button {
                    session.abort()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Stop response")
                .accessibilityLabel("Stop response")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 720)
        .nauvisSurface(cornerRadius: 12)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(labelColor)
            Text(message.text)
                .font(.body)
                .lineSpacing(3)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .nauvisSurface()
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
        case .running: .accentColor
        case .succeeded, .cancelled: .secondary
        case .failed: .red
        }
    }
}

private struct ToolExecutionView: View {
    @ObservedObject var execution: ToolExecution

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text(execution.name)
                        .font(.headline)
                    Spacer()
                    Text(status)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.body, design: .monospaced))
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .nauvisSurface()
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
        case .running: .accentColor
        case .succeeded, .cancelled: .secondary
        case .failed: .red
        }
    }
}

private extension View {
    func nauvisSurface(cornerRadius: CGFloat = 10) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
