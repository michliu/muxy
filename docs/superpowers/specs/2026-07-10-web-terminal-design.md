# Web 终端:浏览器实时接管任意终端 session

- 状态:待实现
- 日期:2026-07-10
- 需求来源:「增加可以透過 web 連線即時編輯任何 session」

## 目标

在浏览器中打开一个网页,实时接管并操作 Muxy 中任意正在运行的终端 pane —— 输入命令、查看输出。等价于给现有 `takeOverPane` 机制加一个浏览器客户端。

## 非目标

- 不做浏览器端代码文件编辑器(本期只做终端 session)。
- 不改动现有 WebSocket RPC 协议,不新增 RPC 方法。
- 不引入运行时 npm / 前端构建链。
- 不做多人协同编辑同一 pane(归属为独占,沿用现有 ownership 模型)。

## 关键约束与结论

- 现有 `MuxyRemoteServer` 用 `NWProtocolWebSocket.Options`(`MuxyServer/MuxyRemoteServer.swift:180`),监听器只接受 WebSocket 握手,普通 `GET /` 无法被正确处理。
- 浏览器 mixed-content 只在「https 页面 → ws://」时触发。只要**页面本身走 http**,即可连本地 `ws://`;WebSocket 不受同源策略限制,跨端口连接可行;PNA 不拦「本地→本地」。
- 结论:**新增一个独立的静态 HTTP 服务发页,页面连原有 ws:// 端口**。对现有 780 行 WS 服务器零改动。

## 架构

```
浏览器 ──GET──▶ [MuxyWebServer: 静态 HTTP, 端口 P2] ──▶ 打包的 web app (xterm.js)
   │
   └──ws://host:P1──▶ [MuxyRemoteServer: 现有 WS 服务器, 不改协议]
                          takeOverPane / terminalInput / terminalOutput ...
```

- 页面走 http、连 ws → 无 mixed-content。
- 两个监听器共用现有 **Mobile 开关**:开关打开时一起起,关闭时一起停。

## 组件

### 1. `MuxyWebServer.swift`(MuxyServer 模块,新增)

- 裸 TCP `NWListener`(不挂 `NWProtocolWebSocket`),手动解析极简 HTTP `GET` 请求。
- 从 bundle 内 `Resources/web-terminal/` 读取静态资源返回,带正确 `Content-Type` 与缓存头。
- 安全:只读、只 `GET`、路径白名单,严防 `../` 目录穿越;不提供任何 RPC 或用户文件访问。
- 生命周期由 `MuxyRemoteServer` 的启停统一驱动(跟随 Mobile 开关)。
- 端口:新增设置 `webTerminalPort`,默认 `4864`(release)/ `4867`(development),避开 WS 的 `4865`/`4866`。端口占用时沿用现有「退回监听器 + 报错 + Free Port」体验。
- 提供 `GET /config.json` → `{ "wsPort": <P1>, "serviceLabel": <name> }`,页面据此拼 `ws://<window.location.hostname>:<wsPort>`。

### 2. `Resources/web-terminal/`(签入前端资源)

- `index.html` / `app.js` / `style.css`。
- **vendored xterm.js**:直接签入 `xterm.min.js` / `xterm.min.css` + fit / canvas addon 的压缩产物,运行时零 npm。
- 连接页:host 取自页面来源,port 取自 `config.json`。
- **视觉方向:尽量贴近 Muxy app**。web 端复刻 Muxy 的深色外壳与视觉语言:
  - 左侧项目栏(project rail)列出项目,进入后展示 worktree。
  - 顶部/侧边**垂直标签**列出 workspace 树里的所有终端 tab(`kind==terminal`,显示 `title`)。
  - 主区按 `WorkspaceDTO.root` 的 `SplitNodeDTO` 递归渲染**分屏结构**(嵌套 flex 布局还原 Muxy 的 split 视觉)。
  - 终端配色采用 `themeChanged` / `pairing` 返回的 fg/bg/palette,与 Muxy 主题一致。
- 每次只对**选中的 pane** 调 `takeOverPane` 并流式渲染(ownership 独占,避免同时占多个 pane);其余 pane 显示占位,点选即切换接管。
- xterm.js 实例渲染选中的 pane。
- 会话状态:`deviceID` + `token` 存 `localStorage`,断线重连复用。

> 说明:web 端是独立前端代码,"贴近 Muxy" 指复刻其配色/布局/标签视觉,并非重建完整 SwiftUI 外壳(命令面板、设置等不在本期)。前端任务以手动验证 + PR 截图/录屏为准(仓库无 JS 测试链);Swift 侧(HTTP 服务、路由、装配)全部 TDD。

### 3. Settings → Mobile(macOS,扩展)

- 新增「Web 终端」状态说明 + 入口 URL + 二维码。
- URL/二维码**不含 token**(与现有配对二维码一致)。

## 数据流

```
连 ws → authenticateDevice
        └─401→ pairDevice → Mac 弹窗审批 → 通过
     → listProjects → selectProject → selectWorktree → getWorkspace
     → 遍历 root 树,列出各 TabDTO.paneID(kind==terminal)
     → 用户点选 pane → takeOverPane(paneID, cols, rows)
        └─ 收 terminalSnapshot 首帧 → term.write
        └─ 持续收 terminalOutput(base64 解码)→ term.write
     → term.onData → terminalInput(base64)   // fire-and-forget
     → fit addon 尺寸变化 → terminalResize
     → 滚轮 → terminalScroll
     → 切换/关闭 → releasePane
```

复用的现有能力:`authenticateDevice`、`pairDevice`、`listProjects`、`selectProject`、`listWorktrees`、`selectWorktree`、`getWorkspace`、`takeOverPane`、`releasePane`、`terminalInput`、`terminalResize`、`terminalScroll`、`getTerminalContent`,以及 `terminalSnapshot` / `terminalOutput` 事件。**无需新增 RPC。**

## 安全

- 复用设备审批 + token:token 仅存 SHA-256 哈希、常量时间比对;首次连触发 Mac 审批。与移动端同一模型,不新增暴露面。
- HTTP 服务只发 bundle 内静态只读资源,GET-only,路径穿越拦截。
- 明文 http/ws,仅限可信局域网(沿用现有文档口径)。URL/二维码不含 token。
- 可选后续加固:WS 服务器目前不校验 `Origin`(移动端亦然);保持一致,不因 web 端新增,作为后续项记录。

## 错误处理

- HTTP:未知路径 `404`,非 GET `405`,畸形请求 `400`,路径穿越拦截;端口占用沿用 WS 现有逻辑。
- WS:复用现有错误码。web app:`401`→配对,`403`→重新配对/拒绝提示,断线→退避重连并**重新 authenticate**(clientID 每连不同,须重取)。
- 归属:`takeOverPane` 会从 Mac/其他客户端抢走 pane(现有行为);web app 跟踪 owner 状态,非 owner 输入被丢弃时给出提示。

## 测试

- Swift 单测(`MuxyWebServer`):合法资源→`200`+正确 `Content-Type`;未知路径→`404`;非 GET→`405`;`../` 穿越→拦截;`/config.json` 返回正确 `wsPort`;并发连接不崩。
- WS 协议零改动,现有测试覆盖。
- web app:核心功能非扩展,不适用 `demo-*` 扩展;前端以手动验证为准,PR 附截图/录屏。

## 文档

- 新增 `docs/remote-server/web-terminal.md`(入口、开关、端口、安全模型)。
- 更新 `docs/remote-server/overview.md` 与 `setup.md`(新端口/开关)。
- `methods.md` 无需改动(纯复用)。扩展 SKILL/文档不受影响(未改扩展 API)。

## 实现影响面

- 新增:`MuxyServer/MuxyWebServer.swift`、`Muxy/Resources/web-terminal/*`、`docs/remote-server/web-terminal.md`。
- 修改:`Package.swift`(打包 `Resources/web-terminal`)、`MuxyRemoteServer` 启停处联动 web 服务、Settings → Mobile UI、Mobile 端口设置旁增 `webTerminalPort`。
- 不改:WS RPC 协议、`MuxyShared` DTO、扩展 API。
