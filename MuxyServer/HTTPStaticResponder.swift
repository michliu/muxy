import Foundation

public enum HTTPStaticResponder {
    public static func response(
        rawRequest: Data,
        resourceRoot: URL,
        config: WebTerminalConfig
    ) -> HTTPStaticResponse {
        guard let head = String(data: rawRequest.prefix(8192), encoding: .utf8),
              let requestLine = head.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first
        else {
            return errorResponse(status: 400, reason: "Bad Request")
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return errorResponse(status: 400, reason: "Bad Request")
        }
        guard parts[0] == "GET" else {
            return errorResponse(status: 405, reason: "Method Not Allowed")
        }

        let target = String(parts[1])
        let pathOnly = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        guard let decoded = pathOnly.removingPercentEncoding else {
            return errorResponse(status: 400, reason: "Bad Request")
        }

        var relative = decoded
        while relative.hasPrefix("/") { relative.removeFirst() }
        if relative.isEmpty { relative = "index.html" }

        if relative == "config.json" {
            return configResponse(config)
        }

        return fileResponse(relative: relative, resourceRoot: resourceRoot)
    }

    public static func contentType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "woff2": "font/woff2"
        case "map": "application/json; charset=utf-8"
        default: "application/octet-stream"
        }
    }

    private static func configResponse(_ config: WebTerminalConfig) -> HTTPStaticResponse {
        let body = (try? JSONEncoder().encode(config)) ?? Data("{}".utf8)
        return HTTPStaticResponse(
            status: 200,
            reason: "OK",
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }

    private static func fileResponse(relative: String, resourceRoot: URL) -> HTTPStaticResponse {
        let root = resourceRoot.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            return errorResponse(status: 403, reason: "Forbidden")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let data = try? Data(contentsOf: candidate)
        else {
            return errorResponse(status: 404, reason: "Not Found")
        }
        return HTTPStaticResponse(
            status: 200,
            reason: "OK",
            contentType: contentType(forPathExtension: candidate.pathExtension),
            body: data
        )
    }

    private static func errorResponse(status: Int, reason: String) -> HTTPStaticResponse {
        HTTPStaticResponse(
            status: status,
            reason: reason,
            contentType: "text/plain; charset=utf-8",
            body: Data("\(status) \(reason)".utf8)
        )
    }
}
