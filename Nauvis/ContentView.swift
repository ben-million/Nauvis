import Bonsplit
import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        BonsplitView(controller: appState.controller) { tab, pane in
            if let session = appState.sessions[tab.id] {
                SessionView(session: session) { message in
                    appState.prompt(message, in: tab.id)
                } onFocus: {
                    appState.controller.focusPane(pane)
                }
            }
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
        .onAppear {
            if appState.controller.allTabIds.isEmpty {
                appState.newSession()
            }
        }
        .onDisappear {
            appState.stopAllSessions()
        }
    }
}

private struct SessionView: View {
    @ObservedObject var session: PiSession
    let onSubmit: (String) -> Void
    let onFocus: () -> Void

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
            inputIsFocused = true
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(session.messages) { message in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(label(for: message.role))
                                .font(.caption2.monospaced())
                                .foregroundStyle(color(for: message.role))
                            Text(message.text)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(message.role == .error ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func label(for role: ConversationMessage.Role) -> String {
        switch role {
        case .user: "YOU"
        case .assistant: "PI"
        case .error: "ERROR"
        }
    }

    private func color(for role: ConversationMessage.Role) -> Color {
        switch role {
        case .user: .secondary
        case .assistant: .accentColor
        case .error: .red
        }
    }
}
