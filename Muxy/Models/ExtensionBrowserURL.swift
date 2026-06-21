import Foundation

enum ExtensionBrowserURL {
    static let allowedSchemes: Set<String> = ["http", "https", "about"]

    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    static func resolve(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), isAllowed(url) {
            return url
        }
        guard looksLikeHost(trimmed), let url = URL(string: "https://\(trimmed)"), isAllowed(url) else {
            return nil
        }
        return url
    }

    private static func looksLikeHost(_ value: String) -> Bool {
        guard !value.contains(" ") else { return false }
        let head = value.split(separator: "/", maxSplits: 1).first.map(String.init) ?? value
        let hostOnly = head.split(separator: ":", maxSplits: 1).first.map(String.init) ?? head
        return hostOnly.contains(".") && !hostOnly.hasPrefix(".") && !hostOnly.hasSuffix(".")
    }
}
