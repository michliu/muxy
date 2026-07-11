# muxy-remote — Ubuntu CLI client

- 状态:待实现
- 日期:2026-07-11
- 需求来源:在 Ubuntu 终端里接管操作 Mac 上 Muxy 的终端 pane(像 `ssh` / `tmux attach`)

## 目标

一个 Go 单静态二进制,从 Ubuntu(含无头服务器)连接 Mac 上 Muxy 的 WebSocket 服务,配对后选择一个终端 pane 并**接管**:本地终端切 raw 模式,与远端 pane 做双向裸管道。

## 非目标

- 不做 GUI(浏览器 web 终端已覆盖图形场景)。
- 不新增任何 Muxy 服务端 RPC —— 纯复用现有手机端协议。
- MVP 不做自动重连、不做 `setClientTheme`(沿用 Mac 主题)。
- 不做多 pane 同时接管(ownership 独占)。

## 关键结论

- `terminalOutput` 推送的是**原始 PTY 字节(ANSI)**。在真实终端里**不需要 VT 模拟器**:字节直写 stdout 由本地终端渲染;stdin 按键直接作 `terminalInput` 发出。这比浏览器客户端更简单。
- 复用端口:release WS `4865`(默认)/ dev `4866`。客户端只连 `host:port`,隧道/网络(LAN / Tailscale / SSH)由用户在运行时选择。

## 架构与数据流

```
muxy-remote --host <ip> [--port 4865]
  └─ WS 连 ws://host:port
     → authenticateDevice ─401→ pairDevice(Mac 弹框批准)→ 存 deviceID+token
     → listProjects → [数字菜单选项目] → selectProject
     → listWorktrees → selectWorktree(单个直接;多个再选)
     → getWorkspace → 遍历 SplitNodeDTO 收集终端 pane → [数字菜单选 pane]
     → takeOverPane(paneID, cols, rows)      // cols/rows 取本地 tty 尺寸
     ── attach 循环 ──
        · 收 terminalSnapshot/terminalOutput → base64 解码 → 写 os.Stdout
        · 读 os.Stdin(raw)→ base64 → terminalInput(fire-and-forget)
        · SIGWINCH → 重取 tty 尺寸 → terminalResize
        · Ctrl-] → releasePane → 恢复 tty → 退出
```

## 组件

`clients/muxy-remote/`(独立 Go module,不入 SPM):

| 文件 | 职责 |
|---|---|
| `main.go` | flag 解析、编排整个流程 |
| `client.go` | WS 连接、`request()` 请求/响应关联(按 id)、事件分发 |
| `protocol.go` | 信封编解码 + DTO 类型(request/response/event、pairing、workspace 树) |
| `pairing.go` | 配对流程 + 持久化 deviceID/token |
| `workspace.go` | 遍历 `SplitNodeDTO` 收集 `kind==terminal` 且有 paneID 的 tab |
| `attach.go` | raw tty、双向流循环、SIGWINCH、detach 键 |
| `picker.go` | 数字菜单选择器 |

**依赖(精简)**:`github.com/coder/websocket`、`golang.org/x/term`、`github.com/google/uuid`、标准库 `encoding/json`。

## 协议映射(复用,零新增)

- 信封:`{ "type":"request", "payload":{ "id", "method", "params" } }`;`params = { "type":<method>, "value":<v> }` 或 `null`。
- 响应:`payload.result.value`(成功)/ `payload.error = { code, message }`(失败)。
- 事件:`payload.event` + `payload.data.value`;`terminalOutput`/`terminalSnapshot` 的 value = `{ paneID, bytes(base64) }`。
- 用到的方法:`authenticateDevice`、`pairDevice`、`listProjects`、`selectProject`、`listWorktrees`、`selectWorktree`、`getWorkspace`、`takeOverPane`、`releasePane`、`terminalInput`、`terminalResize`。
- `terminalInput` fire-and-forget,不等响应。
- workspace 树:`WorkspaceDTO.root` 为 `SplitNodeDTO`:`{type:"tabArea",tabArea:{tabs,activeTabID}}` 或 `{type:"split",split:{direction,ratio,first,second}}`;终端 tab 满足 `kind=="terminal"` 且 `paneID!=null`。

## Attach 机制

- **raw 模式**:`term.MakeRaw(fd)` 保存旧状态;`defer` 恢复;并捕获 SIGINT/SIGTERM 与 panic 也恢复,保证退出后终端不残留 raw。
- **detach 键**:`Ctrl-]`(0x1d)。raw 下按键全透传,用它作转义:按下 → `releasePane` → 恢复 tty → 干净退出。
- **尺寸**:接管时 `term.GetSize` 取列/行;`SIGWINCH` → `terminalResize`。
- **输出**:字节直写 stdout,不解释。

## 配对与配置

- 存 `~/.config/muxy-remote/config.json`:`{ deviceID, token }`(token 首次随机生成,64+ hex)。
- `deviceName` = `muxy-remote (<hostname>)`,便于在 Mac 的 Approved Devices 里辨认。
- 首连 `authenticateDevice`→`401`→`pairDevice`→Mac 批准→存;`403`(token 不符)提示删配置重配对。

## 错误处理

- 连不上 → 明确提示(Muxy 开着吗?Settings→Mobile 开了吗?host/port 对吗?)。
- `takeOverPane` 返回 404 → 该 pane 无活跃 surface,提示重选。
- **任何退出路径都恢复 tty**(核心健壮性)。
- 断线 → 恢复 tty + 打印原因 + 退出(MVP 无自动重连)。

## 测试

- Go 单测(纯逻辑):信封编解码形状、`SplitNodeDTO` 遍历收集 pane、base64 往返。
- 假 WS 服务器测试:跑通 `authenticateDevice`→`401`→`pairDevice`→`takeOverPane` 握手序列与请求/响应关联。
- attach 循环 / 真 tty 属集成,手动验证(连真 Muxy)。

## 分发

- `go build -o muxy-remote ./clients/muxy-remote` → 单静态二进制,`scp` 到任意 Ubuntu 即用,无运行时依赖(headless 可用)。
- README 写清三种连法:LAN 直连 / Tailscale / SSH 隧道。

## 实现影响面

- 新增:`clients/muxy-remote/`(go.mod、*.go、README)。
- 不改:Muxy 主项目、Swift 代码、SPM、服务端协议。
