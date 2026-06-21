import Foundation

enum BrowserPreferences {
    static let embedEnabledKey = "muxy.browser.embedEnabled"

    static var isEmbedEnabled: Bool {
        UserDefaults.standard.object(forKey: embedEnabledKey) as? Bool ?? true
    }

    static func setEmbedEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: embedEnabledKey)
        guard !enabled else { return }
        Task { @MainActor in ExtensionBrowserOverlayRegistry.shared.disableAll() }
    }
}
