import Foundation
import Testing
@testable import MuxyServer

struct MuxyWebServerTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("web-srv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("<html>served</html>".utf8).write(to: root.appendingPathComponent("index.html"))
        return root
    }

    private func waitForStop(_ server: MuxyWebServer) {
        let done = DispatchSemaphore(value: 0)
        server.stop { done.signal() }
        done.wait()
    }

    @Test func servesIndexOverLoopback() async throws {
        let root = try makeRoot()
        let port: UInt16 = 5099
        let server = MuxyWebServer(
            port: port,
            resourceRoot: root,
            config: WebTerminalConfig(wsPort: 4865, serviceLabel: "Mac")
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            server.start { continuation.resume(with: $0) }
        }
        defer { waitForStop(server) }

        let url = URL(string: "http://127.0.0.1:\(port)/")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "<html>served</html>")
    }
}
