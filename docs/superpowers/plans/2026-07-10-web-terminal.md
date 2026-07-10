# Web 终端 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 浏览器打开一个贴近 Muxy app 的网页,实时接管并操作 Muxy 中任意终端 pane。

**Architecture:** 在 `MuxyServer` 模块新增一个只读静态 HTTP 服务(裸 `NWListener`)发打包好的前端;前端(http)连接**原有** WebSocket 服务器(`ws://`),完全复用现有 RPC 与设备配对。两个监听器共用现有 Mobile 开关。

**Tech Stack:** Swift 6 / Network.framework(服务端);原生 JS + vendored xterm.js(前端);SwiftUI(Settings 入口)。

## Global Constraints

- macOS 14+,Swift 6.0+,纯 SPM,无外部依赖管理器,运行时零 npm(xterm.js 以压缩产物签入)。
- 代码库**禁止注释**;所有代码自解释;用早返回,不嵌套。
- 不改动现有 WebSocket RPC 协议,不新增 RPC 方法,不改 `MuxyShared` DTO。
- 前端 HTTP 服务只读、只 `GET`、路径白名单、防 `../` 穿越;不提供 RPC 或用户文件访问。
- 明文 http/ws,仅限可信局域网;URL/二维码不含 token。
- 每完成一个 Swift 任务运行 `scripts/checks.sh --fix`。
- 端口默认:release web `4864`,development web `4867`(WS 为 `4865`/`4866`)。

---

## File Structure

- Create `MuxyServer/WebTerminalConfig.swift` — `/config.json` 的数据形状
- Create `MuxyServer/HTTPStaticResponse.swift` — 响应值类型 + 序列化
- Create `MuxyServer/HTTPStaticResponder.swift` — 纯函数:原始请求 → 响应(可脱离 socket 单测)
- Create `MuxyServer/MuxyWebServer.swift` — `NWListener` 装配
- Create `MuxyServer/Resources/web-terminal/{index.html,style.css,app.js,vendor/*}` — 前端
- Modify `Package.swift` — MuxyServer target 增加 `resources`
- Modify `Muxy/Services/Mobile/MobileServerService.swift` — `webPort` + 联动启停 web 服务
- Modify `Muxy/Views/Settings/MobileSettingsView.swift` — Web 终端入口卡片(URL/QR)
- Modify `Muxy/Views/Settings/Shared/SettingsCatalog.swift` — 注册 webPort 设置项(如需)
- Create `Tests/MuxyTests/Remote/HTTPStaticResponderTests.swift`
- Create `Tests/MuxyTests/Remote/MuxyWebServerTests.swift`
- Create `docs/remote-server/web-terminal.md`;Modify `docs/remote-server/overview.md`、`setup.md`

---

## Task 1: HTTP 静态响应值类型与序列化

**Files:**
- Create: `MuxyServer/WebTerminalConfig.swift`
- Create: `MuxyServer/HTTPStaticResponse.swift`
- Test: `Tests/MuxyTests/Remote/HTTPStaticResponderTests.swift`

**Interfaces:**
- Produces: `WebTerminalConfig(wsPort: UInt16, serviceLabel: String)`;`HTTPStaticResponse(status:reason:contentType:body:)` 与 `func serialized() -> Data`。

- [ ] **Step 1: 写失败测试**

`Tests/MuxyTests/Remote/HTTPStaticResponderTests.swift`:

```swift
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter HTTPStaticResponderTests`
Expected: FAIL(`HTTPStaticResponse` 未定义)。

- [ ] **Step 3: 实现**

`MuxyServer/WebTerminalConfig.swift`:

```swift
import Foundation

public struct WebTerminalConfig: Sendable, Encodable, Equatable {
    public let wsPort: UInt16
    public let serviceLabel: String

    public init(wsPort: UInt16, serviceLabel: String) {
        self.wsPort = wsPort
        self.serviceLabel = serviceLabel
    }
}
```

`MuxyServer/HTTPStaticResponse.swift`:

```swift
import Foundation

public struct HTTPStaticResponse: Sendable, Equatable {
    public let status: Int
    public let reason: String
    public let contentType: String?
    public let body: Data

    public init(status: Int, reason: String, contentType: String?, body: Data) {
        self.status = status
        self.reason = reason
        self.contentType = contentType
        self.body = body
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        if let contentType {
            head += "Content-Type: \(contentType)\r\n"
        }
        head += "Content-Length: \(body.count)\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter HTTPStaticResponderTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add MuxyServer/WebTerminalConfig.swift MuxyServer/HTTPStaticResponse.swift Tests/MuxyTests/Remote/HTTPStaticResponderTests.swift
git commit -m "feat(web): HTTP static response value type"
```

---

## Task 2: HTTP 静态响应器(路由 + 穿越防护 + config.json)

**Files:**
- Create: `MuxyServer/HTTPStaticResponder.swift`
- Test: `Tests/MuxyTests/Remote/HTTPStaticResponderTests.swift`(追加)

**Interfaces:**
- Consumes: `HTTPStaticResponse`、`WebTerminalConfig`。
- Produces: `HTTPStaticResponder.response(rawRequest: Data, resourceRoot: URL, config: WebTerminalConfig) -> HTTPStaticResponse`;`HTTPStaticResponder.contentType(forPathExtension:) -> String`。

- [ ] **Step 1: 写失败测试(追加到同一文件)**

```swift
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
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter HTTPStaticResponderTests`
Expected: FAIL(`HTTPStaticResponder` 未定义)。

- [ ] **Step 3: 实现**

`MuxyServer/HTTPStaticResponder.swift`:

```swift
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
        let root = resourceRoot.standardizedFileURL
        let candidate = root.appendingPathComponent(relative).standardizedFileURL
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
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter HTTPStaticResponderTests`
Expected: PASS(全部)。

- [ ] **Step 5: 提交**

```bash
git add MuxyServer/HTTPStaticResponder.swift Tests/MuxyTests/Remote/HTTPStaticResponderTests.swift
git commit -m "feat(web): static file responder with traversal guard and config.json"
```

---

## Task 3: `MuxyWebServer`(NWListener 装配 + 环回集成测试)

**Files:**
- Create: `MuxyServer/MuxyWebServer.swift`
- Test: `Tests/MuxyTests/Remote/MuxyWebServerTests.swift`

**Interfaces:**
- Consumes: `HTTPStaticResponder`、`WebTerminalConfig`。
- Produces: `MuxyWebServer.defaultPort: UInt16`;`MuxyWebServer(port:resourceRoot:config:)`;`start(completion:)`、`stop(completion:)`。

- [ ] **Step 1: 写失败测试**

`Tests/MuxyTests/Remote/MuxyWebServerTests.swift`:

```swift
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
        defer {
            let done = DispatchSemaphore(value: 0)
            server.stop { done.signal() }
            done.wait()
        }

        let url = URL(string: "http://127.0.0.1:\(port)/")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "<html>served</html>")
    }
}
```

- [ ] **Step 2: 运行,确认失败**

Run: `swift test --filter MuxyWebServerTests`
Expected: FAIL(`MuxyWebServer` 未定义)。

- [ ] **Step 3: 实现**

`MuxyServer/MuxyWebServer.swift`:

```swift
import Foundation
import Network
import os

private let logger = Logger(subsystem: "app.muxy", category: "WebServer")

public final class MuxyWebServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 4864

    private let port: UInt16
    private let resourceRoot: URL
    private let config: WebTerminalConfig
    private let queue = DispatchQueue(label: "app.muxy.webServer")
    private var listener: NWListener?
    private var startCompletion: (@Sendable (Result<Void, Error>) -> Void)?

    public init(port: UInt16, resourceRoot: URL, config: WebTerminalConfig) {
        self.port = port
        self.resourceRoot = resourceRoot
        self.config = config
    }

    public func start(completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            self.startCompletion = completion
            self.startListener()
        }
    }

    public func stop(completion: (@Sendable () -> Void)? = nil) {
        queue.async { [weak self] in
            self?.listener?.cancel()
            self?.listener = nil
            completion?()
        }
    }

    private func startListener() {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            finishStart(.failure(NWError.posix(.EINVAL)))
            return
        }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: endpointPort)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.finishStart(.success(()))
                case let .failed(error):
                    self?.finishStart(.failure(error))
                    self?.listener?.cancel()
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            finishStart(.failure(error))
        }
    }

    private func finishStart(_ result: Result<Void, Error>) {
        guard let completion = startCompletion else { return }
        startCompletion = nil
        completion(result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, accumulated: Data())
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data { buffer.append(data) }

            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(connection, request: buffer)
                return
            }
            if isComplete || error != nil || buffer.count >= 8192 {
                self.respond(connection, request: buffer)
                return
            }
            self.receive(connection, accumulated: buffer)
        }
    }

    private func respond(_ connection: NWConnection, request: Data) {
        let response = HTTPStaticResponder.response(
            rawRequest: request,
            resourceRoot: resourceRoot,
            config: config
        )
        connection.send(content: response.serialized(), isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
```

- [ ] **Step 4: 运行,确认通过**

Run: `swift test --filter MuxyWebServerTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add MuxyServer/MuxyWebServer.swift Tests/MuxyTests/Remote/MuxyWebServerTests.swift
git commit -m "feat(web): static HTTP listener for the web terminal"
```

---

## Task 4: 前端资源(贴近 Muxy 的界面 + xterm.js 协议客户端)

**Files:**
- Create: `MuxyServer/Resources/web-terminal/index.html`
- Create: `MuxyServer/Resources/web-terminal/style.css`
- Create: `MuxyServer/Resources/web-terminal/app.js`
- Create: `MuxyServer/Resources/web-terminal/vendor/xterm.min.js`(签入 @xterm/xterm 5.5.0 UMD 产物)
- Create: `MuxyServer/Resources/web-terminal/vendor/xterm.min.css`
- Create: `MuxyServer/Resources/web-terminal/vendor/addon-fit.min.js`(@xterm/addon-fit 0.10.0 UMD 产物)

**Interfaces:**
- Consumes(运行时):`GET /config.json` → `{ wsPort, serviceLabel }`;`ws://<host>:<wsPort>` 上的既有 RPC/事件。
- Produces:可加载的前端;无 Swift 接口。

本任务无 Swift 自动化测试(仓库无 JS 测试链),以手动验证收尾;协议/xterm 核心给出完整实现。

- [ ] **Step 1: 签入 xterm.js 产物**

从 npm 对应版本取 UMD/压缩产物写入 `vendor/`(锁定版本,后续升级手动替换):
- `@xterm/xterm@5.5.0` 的 `lib/xterm.js`(压缩后)→ `vendor/xterm.min.js`
- `@xterm/xterm@5.5.0` 的 `css/xterm.css` → `vendor/xterm.min.css`
- `@xterm/addon-fit@0.10.0` 的 `lib/addon-fit.js` → `vendor/addon-fit.min.js`

获取方式(在临时目录,不进仓库工具链):

```bash
cd "$(mktemp -d)"
npm pack @xterm/xterm@5.5.0 @xterm/addon-fit@0.10.0
tar -xzf xterm-xterm-5.5.0.tgz
tar -xzf xterm-addon-fit-0.10.0.tgz
```

把 `package/lib/xterm.js`、`package/css/xterm.css`、fit 包的 `package/lib/addon-fit.js` 复制到仓库 `MuxyServer/Resources/web-terminal/vendor/`(重命名如上)。全局 `xterm` 暴露 `Terminal`,fit 暴露 `FitAddon`。

- [ ] **Step 2: `index.html`**

```html
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1" />
    <title>Muxy Web</title>
    <link rel="stylesheet" href="vendor/xterm.min.css" />
    <link rel="stylesheet" href="style.css" />
  </head>
  <body>
    <div id="app">
      <aside id="rail"></aside>
      <nav id="tabs"></nav>
      <main id="stage">
        <section id="terminal"></section>
        <div id="status"></div>
      </main>
    </div>
    <script src="vendor/xterm.min.js"></script>
    <script src="vendor/addon-fit.min.js"></script>
    <script src="app.js"></script>
  </body>
</html>
```

- [ ] **Step 3: `style.css`(贴近 Muxy 深色外壳)**

```css
:root {
  --bg: #1b1b1f;
  --surface: #232329;
  --surface-2: #2b2b33;
  --border: #34343d;
  --fg: #e6e6ea;
  --muted: #9a9aa6;
  --accent: #7c3aed;
}
* { box-sizing: border-box; }
html, body { margin: 0; height: 100%; background: var(--bg); color: var(--fg);
  font: 13px -apple-system, "SF Pro Text", system-ui, sans-serif; }
#app { display: grid; grid-template-columns: 56px 240px 1fr; height: 100vh; }
#rail { background: var(--surface); border-right: 1px solid var(--border);
  display: flex; flex-direction: column; align-items: center; gap: 8px; padding: 10px 0; }
#rail .project { width: 36px; height: 36px; border-radius: 9px; background: var(--surface-2);
  display: grid; place-items: center; cursor: pointer; font-weight: 600; color: var(--muted); }
#rail .project.active { background: var(--accent); color: #fff; }
#tabs { background: var(--surface); border-right: 1px solid var(--border); overflow-y: auto; padding: 8px; }
#tabs .tab { padding: 8px 10px; border-radius: 7px; cursor: pointer; color: var(--muted);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
#tabs .tab.active { background: var(--surface-2); color: var(--fg); }
#stage { display: flex; flex-direction: column; min-width: 0; }
#terminal { flex: 1; min-height: 0; padding: 6px; }
#status { padding: 6px 12px; border-top: 1px solid var(--border); color: var(--muted); font-size: 12px; }
.split { display: flex; gap: 4px; width: 100%; height: 100%; }
.split.vertical { flex-direction: column; }
.pane-slot { flex: 1; border: 1px solid var(--border); border-radius: 8px; overflow: hidden;
  display: grid; place-items: center; color: var(--muted); cursor: pointer; }
.pane-slot.active { border-color: var(--accent); }
```

- [ ] **Step 4: `app.js`(协议客户端 + 导航 + xterm)**

```js
const state = {
  ws: null, clientID: null, reqId: 0, pending: new Map(),
  projects: [], projectID: null, worktreeID: null, workspace: null,
  paneID: null, term: null, fit: null, decoder: new TextDecoder(),
};

function uuid() { return crypto.randomUUID(); }

function deviceCreds() {
  let id = localStorage.getItem("muxy.deviceID");
  let token = localStorage.getItem("muxy.token");
  if (!id) { id = uuid(); localStorage.setItem("muxy.deviceID", id); }
  if (!token) { token = uuid() + uuid(); localStorage.setItem("muxy.token", token); }
  return { id, token };
}

function setStatus(text) { document.getElementById("status").textContent = text; }

async function boot() {
  const config = await fetch("config.json").then((r) => r.json());
  const url = `ws://${location.hostname}:${config.wsPort}`;
  connect(url);
}

function connect(url) {
  setStatus(`Connecting ${url} …`);
  const ws = new WebSocket(url);
  state.ws = ws;
  ws.onopen = () => authenticate();
  ws.onmessage = (e) => onMessage(JSON.parse(e.data));
  ws.onclose = () => { setStatus("Disconnected — retrying in 2s"); setTimeout(() => connect(url), 2000); };
}

function request(method, value) {
  const id = String(++state.reqId);
  const params = value === undefined ? null : { type: method, value };
  const frame = { type: "request", payload: { id, method, params } };
  if (method !== "terminalInput") {
    return new Promise((resolve, reject) => {
      state.pending.set(id, { resolve, reject });
      state.ws.send(JSON.stringify(frame));
    });
  }
  state.ws.send(JSON.stringify(frame));
  return Promise.resolve();
}

async function authenticate() {
  const { id, token } = deviceCreds();
  const value = { deviceID: id, deviceName: deviceName(), token, theme: null };
  try {
    const result = await request("authenticateDevice", value);
    onAuthenticated(result);
  } catch (err) {
    if (err.code === 401) {
      setStatus("Waiting for approval on your Mac …");
      try {
        const result = await request("pairDevice", value);
        onAuthenticated(result);
      } catch (pairErr) {
        setStatus(`Pairing denied (${pairErr.code || "error"})`);
      }
    } else {
      setStatus(`Auth failed (${err.code || "error"})`);
    }
  }
}

function deviceName() {
  const ua = navigator.userAgent;
  const browser = /Chrome/.test(ua) ? "Chrome" : /Firefox/.test(ua) ? "Firefox" : /Safari/.test(ua) ? "Safari" : "Browser";
  return `Web (${browser})`;
}

async function onAuthenticated(pairing) {
  state.clientID = pairing.clientID;
  setStatus("Connected");
  ensureTerminal(pairing);
  state.projects = await request("listProjects");
  renderRail();
}

function onMessage(frame) {
  if (frame.type === "response") return onResponse(frame.payload);
  if (frame.type === "event") return onEvent(frame.payload);
}

function onResponse(payload) {
  const waiter = state.pending.get(payload.id);
  if (!waiter) return;
  state.pending.delete(payload.id);
  if (payload.error) { waiter.reject(payload.error); return; }
  waiter.resolve(payload.result ? payload.result.value : undefined);
}

function onEvent(payload) {
  const data = payload.data && payload.data.value;
  switch (payload.event) {
    case "terminalSnapshot":
    case "terminalOutput":
      if (data && data.paneID === state.paneID) writeBytes(data.bytes);
      break;
    case "workspaceChanged":
      if (data && data.projectID === state.projectID) { state.workspace = data; renderTabs(); }
      break;
    case "themeChanged":
      if (data) applyTheme(data.fg, data.bg, data.palette);
      break;
    default:
      break;
  }
}

function ensureTerminal(pairing) {
  if (state.term) return;
  const term = new Terminal({ cursorBlink: true, fontFamily: "SF Mono, Menlo, monospace", fontSize: 13, allowProposedApi: true });
  const fit = new FitAddon.FitAddon();
  term.loadAddon(fit);
  term.open(document.getElementById("terminal"));
  fit.fit();
  term.onData((input) => {
    if (!state.paneID) return;
    request("terminalInput", { paneID: state.paneID, bytes: btoa(input) });
  });
  window.addEventListener("resize", () => resizePane());
  state.term = term; state.fit = fit;
  if (pairing.themeFg !== undefined) applyTheme(pairing.themeFg, pairing.themeBg, pairing.themePalette);
}

function writeBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  state.term.write(bytes);
}

function hex(color) { return "#" + (color >>> 0).toString(16).padStart(6, "0"); }

function applyTheme(fg, bg, palette) {
  if (!state.term || fg === undefined || bg === undefined) return;
  const theme = { foreground: hex(fg), background: hex(bg) };
  if (Array.isArray(palette)) {
    const names = ["black","red","green","yellow","blue","magenta","cyan","white",
      "brightBlack","brightRed","brightGreen","brightYellow","brightBlue","brightMagenta","brightCyan","brightWhite"];
    palette.slice(0, 16).forEach((c, i) => { theme[names[i]] = hex(c); });
  }
  state.term.options.theme = theme;
  document.documentElement.style.setProperty("--bg", hex(bg));
  document.documentElement.style.setProperty("--fg", hex(fg));
}

function renderRail() {
  const rail = document.getElementById("rail");
  rail.innerHTML = "";
  state.projects.forEach((project) => {
    const el = document.createElement("div");
    el.className = "project" + (project.id === state.projectID ? " active" : "");
    el.textContent = project.name.slice(0, 1).toUpperCase();
    el.title = project.name;
    el.onclick = () => selectProject(project.id);
    rail.appendChild(el);
  });
}

async function selectProject(projectID) {
  state.projectID = projectID;
  await request("selectProject", { projectID });
  const worktrees = await request("listWorktrees", { projectID });
  state.worktreeID = worktrees[0] ? worktrees[0].id : null;
  if (state.worktreeID) await request("selectWorktree", { projectID, worktreeID: state.worktreeID });
  state.workspace = await request("getWorkspace", { projectID });
  renderRail();
  renderTabs();
}

function collectTabs(node, acc) {
  if (!node) return acc;
  if (node.type === "tabArea") {
    node.tabArea.tabs.forEach((tab) => { if (tab.kind === "terminal" && tab.paneID) acc.push(tab); });
  } else if (node.type === "split") {
    collectTabs(node.split.first, acc);
    collectTabs(node.split.second, acc);
  }
  return acc;
}

function renderTabs() {
  const tabsEl = document.getElementById("tabs");
  tabsEl.innerHTML = "";
  const tabs = state.workspace ? collectTabs(state.workspace.root, []) : [];
  tabs.forEach((tab) => {
    const el = document.createElement("div");
    el.className = "tab" + (tab.paneID === state.paneID ? " active" : "");
    el.textContent = tab.title || "Terminal";
    el.onclick = () => attachPane(tab.paneID);
    tabsEl.appendChild(el);
  });
  if (!state.paneID && tabs[0]) attachPane(tabs[0].paneID);
}

async function attachPane(paneID) {
  if (state.paneID === paneID) return;
  if (state.paneID) await request("releasePane", { paneID: state.paneID });
  state.paneID = paneID;
  state.term.reset();
  const { cols, rows } = state.term;
  await request("takeOverPane", { paneID, cols, rows });
  renderTabs();
  setStatus(`Attached to pane`);
}

function resizePane() {
  if (!state.fit || !state.paneID) return;
  state.fit.fit();
  const { cols, rows } = state.term;
  request("terminalResize", { paneID: state.paneID, cols, rows });
}

boot();
```

> 说明:错误对象取自响应 `payload.error`(含 `code`/`message`),`request` 的 reject 值即该对象,故 `err.code` 可用。`takeOverPane`/`terminalResize` 的 `cols`/`rows` 直接取自 xterm 的当前网格。

- [ ] **Step 5: 手动验证(临时用一个静态服务先验证前端逻辑)**

在资源目录起一个临时静态服务并手动放一个 `config.json` 指向本地运行中的 Muxy WS 端口:

```bash
cd MuxyServer/Resources/web-terminal
printf '{"wsPort":4866,"serviceLabel":"Dev"}' > config.json   # 仅本地验证用,勿提交
python3 -m http.server 8000
```

浏览器打开 `http://localhost:8000`,确认:出现 Mac 审批弹窗 → 批准后列出项目 → 选项目列出终端 tab → 点 tab 能看到当前屏幕并可输入。验证后删除临时 `config.json`。

- [ ] **Step 6: 提交(不含临时 config.json)**

```bash
git add MuxyServer/Resources/web-terminal
git commit -m "feat(web): Muxy-styled browser terminal frontend with xterm.js"
```

---

## Task 5: 打包前端资源到 MuxyServer target

**Files:**
- Modify: `Package.swift`(MuxyServer target)
- Create: `MuxyServer/WebTerminalResources.swift`

**Interfaces:**
- Produces:`WebTerminalResources.rootURL: URL?`(供 App 侧定位打包后的前端目录)。

- [ ] **Step 1: 在 Package.swift 给 MuxyServer 增加 resources**

`Package.swift` 中 MuxyServer target 改为:

```swift
.target(
    name: "MuxyServer",
    dependencies: [
        "MuxyShared",
    ],
    path: "MuxyServer",
    resources: [
        .copy("Resources/web-terminal"),
    ]
),
```

- [ ] **Step 2: 资源定位 helper**

`MuxyServer/WebTerminalResources.swift`:

```swift
import Foundation

public enum WebTerminalResources {
    public static var rootURL: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("web-terminal", isDirectory: true)
    }
}
```

- [ ] **Step 3: 构建确认(资源存在)**

Run: `swift build`
Expected: 成功;`Bundle.module` 由 SPM 自动合成(target 现有资源)。

- [ ] **Step 4: 提交**

```bash
git add Package.swift MuxyServer/WebTerminalResources.swift
git commit -m "build(web): bundle web-terminal resources into MuxyServer"
```

---

## Task 6: 在 MobileServerService 联动启停 web 服务

**Files:**
- Modify: `Muxy/Services/Mobile/MobileServerService.swift`

**Interfaces:**
- Consumes:`MuxyWebServer`、`WebTerminalConfig`、`WebTerminalResources.rootURL`。
- Produces:`MobileServerService.shared.webPort: UInt16`;`MobileServerService.defaultWebPort: UInt16`;`webURLString(host:) -> String?`。

- [ ] **Step 1: 加 web 端口常量与存储**

在 `MobileServerService` 顶部常量区加(紧邻 `defaultPort`):

```swift
static let defaultWebPort: UInt16 = AppEnvironment.isDevelopment
    ? MuxyWebServer.defaultPort + 3
    : MuxyWebServer.defaultPort

static var webPortKey: String {
    AppEnvironment.isDevelopment
        ? "app.muxy.mobile.webPort.dev"
        : "app.muxy.mobile.webPort"
}
```

(release `4864`,development `4867`。)

- [ ] **Step 2: 加 web 端口属性与 web 服务器字段**

在 `private var server: MuxyRemoteServer?` 附近加:

```swift
private var webServer: MuxyWebServer?

private(set) var webPort: UInt16 {
    didSet { UserDefaults.standard.set(Int(webPort), forKey: Self.webPortKey) }
}
```

在 `init` 里,`port` 初始化之后加:

```swift
let storedWebPort = UserDefaults.standard.object(forKey: Self.webPortKey) as? Int
if let storedWebPort, let value = UInt16(exactly: storedWebPort), Self.isValid(port: value) {
    webPort = value
} else {
    webPort = Self.defaultWebPort
}
```

(注意:`webPort` 是非可选存储属性,须在 `init` 中所有分支前赋值;把上面这段放在两条 `port = …` 之后、`ApprovedDevicesStore` 之前即可,`self.` 前缀按 Swift 规则可省。)

- [ ] **Step 3: 在 WS 成功启动后拉起 web 服务,停止时一并停**

在 `handleStartResult` 的 `.success` 分支末尾加:

```swift
startWebServer(wsPort: port)
```

在 `retireCurrentServer()` 开头(`guard let current` 之前)加:

```swift
stopWebServer()
```

新增两个方法:

```swift
private func startWebServer(wsPort: UInt16) {
    stopWebServer()
    guard let root = WebTerminalResources.rootURL else {
        logger.error("Web terminal resources missing")
        return
    }
    let config = WebTerminalConfig(wsPort: wsPort, serviceLabel: Host.current().localizedName ?? "Muxy")
    let server = MuxyWebServer(port: webPort, resourceRoot: root, config: config)
    webServer = server
    server.start { result in
        if case let .failure(error) = result {
            logger.error("Web server failed to start on port \(self.webPort): \(error.localizedDescription)")
        }
    }
    logger.info("Web terminal server starting on port \(self.webPort)")
}

private func stopWebServer() {
    webServer?.stop()
    webServer = nil
}
```

在 `stopForTermination()` 里也加 `stopWebServer()`。

- [ ] **Step 4: web URL 构造 helper**

在类型末尾加:

```swift
func webURLString(host: String) -> String {
    "http://\(host):\(webPort)"
}
```

- [ ] **Step 5: 构建 + 现有测试回归**

Run: `swift build && swift test --filter MobileServer`
Expected: 编译通过;现有测试不回归(该文件无既有单测则以编译通过为准)。

- [ ] **Step 6: 提交**

```bash
git add Muxy/Services/Mobile/MobileServerService.swift
git commit -m "feat(web): start web terminal server alongside the mobile server"
```

---

## Task 7: Settings → Mobile 增加 Web 终端入口卡片

**Files:**
- Modify: `Muxy/Views/Settings/MobileSettingsView.swift`

**Interfaces:**
- Consumes:`MobileServerService.webURLString(host:)`、`MobilePairingService.availableHosts()`、`MobilePairingHost.host`、`MobilePairingQRView`。

- [ ] **Step 1: 在配对卡片 section 之后插入 Web 终端 section**

在 `body` 里 `Pair Mobile Device` 的 `SettingsSection { … }` 之后、`Approved Devices` section 之前插入:

```swift
if service.isEnabled, let selectedHost {
    let webURL = service.webURLString(host: selectedHost.host)
    SettingsSection(
        "Web Terminal",
        footer: "Open this URL in a browser on the same network to control any terminal session. First use still needs your approval on this Mac."
    ) {
        webTerminalCard(url: webURL)
    }
}
```

- [ ] **Step 2: 新增 webTerminalCard 视图方法**

在 `pairingCard(host:uri:)` 方法附近加:

```swift
private func webTerminalCard(url: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
        MobilePairingQRView(uriString: url, size: 132)
        VStack(alignment: .leading, spacing: 6) {
            Text("Open in any browser on this network:")
                .font(.system(size: SettingsMetrics.labelFontSize))
                .fixedSize(horizontal: false, vertical: true)
            Text(url)
                .font(.system(size: SettingsMetrics.labelFontSize, design: .monospaced))
                .foregroundStyle(SettingsStyle.foreground)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                copyPairingLink(url)
            } label: {
                Label(
                    didCopyPairingLink ? "Copied" : "Copy URL",
                    systemImage: didCopyPairingLink ? "checkmark" : "doc.on.doc"
                )
                .font(.system(size: SettingsMetrics.footnoteFontSize, weight: .medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(MuxyTheme.accent)
        }
        Spacer(minLength: 0)
    }
    .padding(.horizontal, SettingsMetrics.horizontalPadding)
    .padding(.vertical, SettingsMetrics.rowVerticalPadding)
}
```

- [ ] **Step 3: 构建**

Run: `swift build`
Expected: 成功。

- [ ] **Step 4: 手动验证(用户运行 app)**

打开 Settings → Mobile,启用后应看到 "Web Terminal" 卡片,含二维码与 `http://<host>:<webPort>`;浏览器打开该 URL 触发审批 → 可操作终端。截图/录屏留作 PR。

- [ ] **Step 5: 提交**

```bash
git add Muxy/Views/Settings/MobileSettingsView.swift
git commit -m "feat(web): web terminal entry card in Mobile settings"
```

---

## Task 8: 文档

**Files:**
- Create: `docs/remote-server/web-terminal.md`
- Modify: `docs/remote-server/overview.md`
- Modify: `docs/remote-server/setup.md`

**Interfaces:** 无代码接口。

- [ ] **Step 1: 新增 web-terminal.md**

`docs/remote-server/web-terminal.md`:

```markdown
# Web Terminal

Muxy serves a browser client that takes over any terminal pane in real time. It reuses the same WebSocket RPC and device-pairing model as the mobile companions — the browser is just another approved device.

## How it works

- A read-only static HTTP server ships the bundled web app (`http://<host>:<webPort>`, default `4864` release / `4867` development).
- The page connects back to the WebSocket server (`ws://<host>:<port>`). Because the page is served over `http`, there is no mixed-content block.
- Enable it from **Settings → Mobile** — the same toggle that starts the mobile server also starts the web server. The panel shows the URL and a QR code (no token).

## Using it

1. Enable **Allow mobile device connections** on the Mac.
2. Open the Web Terminal URL in a browser on the same network.
3. Approve the browser on the Mac the first time (same pairing sheet as mobile).
4. Pick a project, then a terminal tab; the browser takes over that pane and streams it live.

## Security

- `http`/`ws` on the local network only — treat as trusted-LAN unless tunneled (e.g. Tailscale).
- The HTTP server is read-only, GET-only, and serves only bundled assets; it exposes no RPC and no filesystem access. The URL/QR never carry a token.
- Pane control is ownership-based: taking over a pane in the browser takes it from the Mac until released.
```

- [ ] **Step 2: overview.md 增加页表条目**

在 `## Pages` 表格里 `Data Objects` 行后加:

```markdown
| [Web Terminal](web-terminal.md) | Browser client, how it's served, and the shared pairing model |
```

- [ ] **Step 3: setup.md 补 web 端口说明**

在 `## Enabling the server` 表格后加一段:

```markdown
Enabling the mobile server also starts a **read-only static HTTP server** for the [Web Terminal](web-terminal.md) on `webPort` (default `4864` release / `4867` development). It only serves the bundled browser app; all control still flows over the WebSocket server.
```

- [ ] **Step 4: 提交**

```bash
git add docs/remote-server/web-terminal.md docs/remote-server/overview.md docs/remote-server/setup.md
git commit -m "docs(web): document the web terminal"
```

---

## Task 9: 全量校验

- [ ] **Step 1: 跑完整检查**

Run: `scripts/checks.sh --fix`
Expected: format/lint/build/test 全绿。

- [ ] **Step 2: 提交任何自动修复**

```bash
git add -A
git commit -m "chore(web): apply format and lint fixes"
```

---

## Self-Review

- **Spec 覆盖**:HTTP 服务(Task 1-3、5)、前端贴近 Muxy(Task 4)、复用配对与 RPC(Task 4 的 app.js)、Mobile 开关联动(Task 6)、Settings 入口(Task 7)、安全只读/穿越防护(Task 2)、文档(Task 8)。均有对应任务。
- **占位符**:无 TBD/TODO;每个代码步骤含完整代码。
- **类型一致**:`WebTerminalConfig(wsPort:serviceLabel:)`、`HTTPStaticResponse(status:reason:contentType:body:)`、`HTTPStaticResponder.response(rawRequest:resourceRoot:config:)`、`MuxyWebServer(port:resourceRoot:config:)`、`WebTerminalResources.rootURL`、`MobileServerService.webPort` / `webURLString(host:)` 在各任务间名称一致。
- **前端无 Swift 测试**:已在 Task 4 显式说明,并给出手动验证步骤,符合仓库现状(无 JS 测试链)。
