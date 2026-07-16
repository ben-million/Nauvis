import Bonsplit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    let controller: BonsplitController
    @Published private(set) var sessions: [TabID: PiSession] = [:]
    @Published private(set) var toolCallTabs: [TabID: ToolExecution] = [:]

    private let workingDirectory: URL
    private var sessionNumber = 0

    init() {
        let configuration = BonsplitConfiguration(contentViewLifecycle: .recreateOnSwitch)
        controller = BonsplitController(configuration: configuration)

        let currentDirectory = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["NAUVIS_CWD"]
                ?? FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
        workingDirectory = currentDirectory.path == "/"
            ? FileManager.default.homeDirectoryForCurrentUser
            : currentDirectory

        controller.delegate = self
        startInitialSession()
    }

    func newSession(inPane pane: PaneID? = nil) {
        sessionNumber += 1
        guard let tabID = controller.createTab(
            title: "Session \(sessionNumber)",
            icon: nil,
            inPane: pane
        ) else { return }

        sessions[tabID] = PiSession(workingDirectory: workingDirectory)
    }

    private func startInitialSession() {
        guard let tabID = controller.allTabIds.first else {
            newSession()
            return
        }

        sessionNumber += 1
        controller.updateTab(
            tabID,
            title: "Session \(sessionNumber)",
            icon: .some(nil)
        )
        sessions[tabID] = PiSession(workingDirectory: workingDirectory)
    }

    func closeCurrentTab() {
        guard
            let pane = controller.focusedPaneId,
            let tab = controller.selectedTab(inPane: pane)
        else { return }
        controller.closeTab(tab.id)
    }

    func stopAllSessions() {
        for session in sessions.values {
            session.stop()
        }
    }

    func prompt(_ message: String, in tabID: TabID) {
        guard let session = sessions[tabID] else { return }
        let shouldNameSession = !session.hasUserMessages
        session.prompt(message)

        if shouldNameSession {
            let title = sessionTitle(for: message)
            controller.updateTab(tabID, title: title)
            session.setName(title)
        }
    }

    func openToolCall(_ execution: ToolExecution, from pane: PaneID) {
        if let tabID = toolCallTabs.first(where: { $0.value === execution })?.key {
            controller.selectTab(tabID)
            return
        }

        guard let tabID = controller.createTab(
            title: execution.name,
            icon: nil,
            inPane: pane
        ) else { return }

        toolCallTabs[tabID] = execution
    }

    private func sessionTitle(for message: String) -> String {
        let title = message
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "New Session"
        return title.count > 32 ? "\(title.prefix(31))…" : title
    }
}

extension AppState: BonsplitDelegate {
    func splitTabBar(
        _ controller: BonsplitController,
        didCloseTab tabID: TabID,
        fromPane pane: PaneID
    ) {
        sessions.removeValue(forKey: tabID)?.stop()
        toolCallTabs.removeValue(forKey: tabID)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    ) {
        newSession(inPane: newPane)
    }
}
