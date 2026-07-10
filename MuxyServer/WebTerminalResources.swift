import Foundation

public enum WebTerminalResources {
    public static var rootURL: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("web-terminal", isDirectory: true)
    }
}
