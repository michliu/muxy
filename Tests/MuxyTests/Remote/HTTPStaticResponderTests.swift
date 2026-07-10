import Foundation
import Testing
@testable import MuxyServer

struct HTTPStaticResponderTests {
    @Test func serializesStatusLineAndHeaders() {
        let response = HTTPStaticResponse(
            status: 200,
            reason: "OK",
            contentType: "text/plain",
            body: Data("hi".utf8)
        )
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: text/plain\r\n"))
        #expect(text.contains("Content-Length: 2\r\n"))
        #expect(text.contains("Connection: close\r\n"))
        #expect(text.hasSuffix("\r\n\r\nhi"))
    }

    @Test func omitsContentTypeWhenNil() {
        let response = HTTPStaticResponse(status: 404, reason: "Not Found", contentType: nil, body: Data())
        let text = String(decoding: response.serialized(), as: UTF8.self)
        #expect(!text.contains("Content-Type:"))
        #expect(text.contains("Content-Length: 0\r\n"))
    }
}

extension HTTPStaticResponderTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-term-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("<html>root</html>".utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("body{}".utf8).write(to: root.appendingPathComponent("style.css"))
        return root
    }

    private var config: WebTerminalConfig { WebTerminalConfig(wsPort: 4865, serviceLabel: "Mac") }

    @Test func servesIndexForRoot() throws {
        let root = try makeRoot()
        let response = HTTPStaticResponder.response(
            rawRequest: Data("GET / HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
            resourceRoot: root,
            config: config
        )
        #expect(response.status == 200)
        #expect(response.contentType == "text/html; charset=utf-8")
        #expect(String(decoding: response.body, as: UTF8.self) == "<html>root</html>")
    }

    @Test func servesConfigJSON() throws {
        let root = try makeRoot()
        let response = HTTPStaticResponder.response(
            rawRequest: Data("GET /config.json HTTP/1.1\r\n\r\n".utf8),
            resourceRoot: root,
            config: config
        )
        #expect(response.status == 200)
        #expect(response.contentType == "application/json; charset=utf-8")
        let json = try JSONSerialization.jsonObject(with: response.body) as? [String: Any]
        #expect(json?["wsPort"] as? Int == 4865)
        #expect(json?["serviceLabel"] as? String == "Mac")
    }

    @Test func returns404ForMissingFile() throws {
        let root = try makeRoot()
        let response = HTTPStaticResponder.response(
            rawRequest: Data("GET /missing.js HTTP/1.1\r\n\r\n".utf8),
            resourceRoot: root,
            config: config
        )
        #expect(response.status == 404)
    }

    @Test func returns405ForNonGet() throws {
        let root = try makeRoot()
        let response = HTTPStaticResponder.response(
            rawRequest: Data("POST / HTTP/1.1\r\n\r\n".utf8),
            resourceRoot: root,
            config: config
        )
        #expect(response.status == 405)
    }

    @Test func returns400ForMalformedRequestLine() throws {
        let root = try makeRoot()
        let response = HTTPStaticResponder.response(
            rawRequest: Data("garbage\r\n\r\n".utf8),
            resourceRoot: root,
            config: config
        )
        #expect(response.status == 400)
    }

    @Test func blocksPathTraversal() throws {
        let root = try makeRoot()
        let parent = root.deletingLastPathComponent()
        try Data("secret".utf8).write(to: parent.appendingPathComponent("secret.txt"))
        let response = HTTPStaticResponder.response(
            rawRequest: Data("GET /../secret.txt HTTP/1.1\r\n\r\n".utf8),
            resourceRoot: root,
            config: config
        )
        #expect(response.status == 403 || response.status == 404)
        #expect(String(decoding: response.body, as: UTF8.self) != "secret")
    }
}
