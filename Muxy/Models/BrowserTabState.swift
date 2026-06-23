import AppKit
import Foundation

@MainActor
@Observable
final class BrowserTabState: Identifiable {
    enum NavigationCommand: Equatable {
        case back
        case forward
        case reload
        case stop
        case zoomIn
        case zoomOut
        case zoomReset
        case inspectElement
    }

    struct FindRequest: Equatable {
        let query: String
        let backwards: Bool
    }

    let id = UUID()
    let projectPath: String
    var profileID: UUID

    var url: URL?
    var pendingURL: URL?
    var pendingCommand: NavigationCommand?
    var pageTitle: String?
    var customTitle: String?
    var canGoBack: Bool = false
    var canGoForward: Bool = false
    var isLoading: Bool = false
    var estimatedProgress: Double = 0
    var shouldFocusAddressOnOpen = true
    var pageZoom: Double = 1
    var loadError: BrowserLoadError?
    var faviconURL: URL?
    var faviconImage: NSImage?
    var pendingFind: FindRequest?
    var findActivationToken = 0
    var findFoundMatch = true

    var isBlank: Bool {
        guard let absoluteString = url?.absoluteString else { return true }
        return BrowserHomePage.isBlankMode(absoluteString)
    }

    var displayTitle: String {
        if let customTitle, !customTitle.isEmpty { return customTitle }
        if let pageTitle, !pageTitle.isEmpty { return pageTitle }
        if let host = url?.host { return host }
        return "New Tab"
    }

    init(projectPath: String, url: URL? = nil, profileID: UUID = BrowserProfile.defaultID) {
        self.projectPath = projectPath
        self.url = url
        self.profileID = profileID
        pendingURL = url
    }

    func load(from input: String) {
        guard let resolved = BrowserURL.resolve(from: input) else { return }
        pendingURL = resolved
    }

    func activateFind() {
        findActivationToken += 1
    }
}
