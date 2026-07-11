# muxy-remote 轻量 TUI

- 状态:待实现
- 日期:2026-07-11
- 需求来源:把 muxy-remote 的数字菜单升级为 Bubble Tea 会话浏览器,可搜索、可在 pane 间快速切换

## 目标

给 `clients/muxy-remote/` 加一个轻量 TUI:一个 Bubble Tea "会话浏览器",可搜索选择终端会话;`Enter` 接管(仍走现有 raw 透传),`Ctrl-]` 分离**回到浏览器**而非退出,从而在多个 pane 之间快速切换。有真终端时默认走 TUI,非-tty 环境回退到现有数字菜单。

## 非目标

- 不做完整 tmux 式同屏合成(不引入 VT 模拟器)。终端接管始终是全屏 raw 透传。
- 不新增任何 Muxy 服务端 RPC。
- 不做跨项目的全局会话列表;浏览器范围是**单个 worktree**。
- MVP 不做自动重连(与现有 CLI 一致)。

## 关键结论

- **避开 VT 模拟**:浏览器(Bubble Tea)与终端(raw 透传)**交替占屏**。接管时用 `tea.Exec` 把终端交给 `runAttach`,Bubble Tea 自动 Release/Restore 终端。
- 复用现有 `client.go`(含可切换 sink)、`workspace.go`(`collectTerminalPanes`)、`attach.go`(`runAttach`)、`creds.go`、`picker.go`,不改协议。

## 架构

```
main: term.IsTerminal(stdin fd)?
  ├─ 是 → runTUI()
  └─ 否 → 现有数字菜单流程(保留)

runTUI:
  loadOrCreateCreds → dial → authenticate(复用)
  Bubble Tea 三屏状态机:
    项目选择(可搜索列表)→ worktree 选择(单个自动跳过)→ 会话浏览器
  会话浏览器(单 worktree):
    · 列出 kind==terminal 的会话;/ 搜索,↑↓/jk 移动
    · 每项标记归属:● 当前接管 / ▣ Mac 占用 / ○ 其他客户端
    · 列表随 workspaceChanged 实时增删(保留选中/过滤)
    · Enter → tea.Exec(attachCmd) → runAttach(raw 透传);Ctrl-] 分离回浏览器
    · Esc → 返回上一层;q / Ctrl-C → 退出
    · 底部状态行:连接状态点 + 当前 worktree + 键位提示
```

## sink 切换

复用 `client` 的可切换 sink:
- **浏览期**:sink = 把 `workspaceChanged` / `paneOwnershipChanged` 通过 `program.Send()` 投递给 TUI,刷新列表/归属。
- **接管期**:`runAttach` 把 sink 换成写 stdout(现状),其 defer 复位为 no-op。
- **分离后**:`attachDoneMsg` 触发 TUI 重新装回浏览 sink,并刷新列表。

## 组件

`clients/muxy-remote/` 增量:

| 文件 | 职责 |
|---|---|
| `tui.go` | Bubble Tea model(三屏状态)+ Update/View + 会话列表构建 + 归属 map;`runTUI(client, creds)` 入口 |
| `tuiattach.go` | `tea.Exec` 的 attach 命令(实现 `tea.ExecCommand`,包 `runAttach`) |
| `main.go`(改) | tty 判断 → `runTUI` 或现有数字菜单流程 |

**依赖新增**:`github.com/charmbracelet/bubbletea`、`github.com/charmbracelet/bubbles`(list 组件)、`github.com/charmbracelet/lipgloss`(样式)。

## 数据流要点

- 项目/worktree 列表:复用 `listProjects` / `listWorktrees` / `selectProject` / `selectWorktree`。
- 会话列表:进入时 `getWorkspace` 拉一次;`workspaceChanged` 事件的 `data.value` 即完整 workspace 树,直接 `collectTerminalPanes` 重建列表(保留当前选中/过滤)。
- 归属:`map[paneID]owner`,由 `paneOwnershipChanged` 事件更新;外加"当前接管的 paneID"。
- 接管:`Enter` → model 返回 `tea.Exec(attachCmd, onDone)`;Bubble Tea 自动 Release 终端 → `runAttach` 跑 → 返回 → 自动 Restore → `attachDoneMsg` → 重装浏览 sink + 刷新。

### 归属标记的已知限制

服务端没有"按需查询 pane 归属"的 RPC,归属只能从**连接期间**到达的 `paneOwnershipChanged` 事件(以及自己接管的 pane)得知。因此**刚进入浏览器时多为未知/空白**,他人占用会在事件到达时点亮。此为 MVP 可接受的限制。

## 错误处理

- 非 tty(`term.IsTerminal`=false)→ 无缝走数字菜单。
- 连接/认证失败(TUI 未起)→ 纯文本报错退出(同现状)。
- 接管中断线 → `runAttach` 返回 error → `attachDoneMsg` 带错 → 浏览器提示"已断开"后退出(MVP 不自动重连)。
- 退出必恢复终端:Bubble Tea 管理 alt-screen 恢复;`runAttach` 内已有 raw 恢复 + SIGINT/SIGTERM/SIGHUP 处理。

## 测试

- 纯逻辑单测:workspace 树 → 会话 items 构建;`workspaceChanged` 刷新保留选中;归属 map 更新;`Enter` 在会话上返回 attach 命令(直接调 `model.Update` 断言返回的 `tea.Cmd` 类型/model 状态)。
- `bubbles/list` 的过滤/导航由库保证,不重复测。
- 真实 Release/Restore + raw 接管:集成/手动(tty 里连真 Muxy)。

## 分发

- 仍是单静态二进制;交叉编译方式不变(`CGO_ENABLED=0 GOOS=linux GOARCH=… go build`)。
- 更新 `clients/muxy-remote/README.md`:说明默认 TUI + 键位 + 非-tty 回退。

## 实现影响面

- 新增:`clients/muxy-remote/tui.go`、`tuiattach.go`、测试。
- 修改:`clients/muxy-remote/main.go`(tty 分流)、`go.mod`/`go.sum`(TUI 依赖)、`README.md`。
- 不改:Muxy 主项目、服务端协议、现有 client/workspace/attach/creds/picker 逻辑。
