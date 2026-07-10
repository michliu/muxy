const state = {
  ws: null, clientID: null, reqId: 0, pending: new Map(),
  projects: [], projectID: null, worktrees: [], worktreeID: null, workspace: null,
  paneID: null, term: null, fit: null, termHost: null,
};

function uuid() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10, 16).join("")}`;
}

function deviceCreds() {
  let id = localStorage.getItem("muxy.deviceID");
  let token = localStorage.getItem("muxy.token");
  if (!id) { id = uuid(); localStorage.setItem("muxy.deviceID", id); }
  if (!token) { token = uuid() + uuid(); localStorage.setItem("muxy.token", token); }
  return { id, token };
}

function setStatus(text, connState) {
  document.getElementById("status-text").textContent = text;
  if (connState) document.getElementById("status").dataset.state = connState;
  updateOverlay();
}

function overlaySub(connState) {
  if (connState === "connecting") return "Approve this device on your Mac if prompted.";
  if (connState === "error") return "Reconnecting automatically…";
  if (state.projectID) return "Select or open a terminal session.";
  if (state.projects.length) return "Pick a project on the left to begin.";
  return "";
}

function updateOverlay() {
  const overlay = document.getElementById("overlay");
  if (!overlay) return;
  overlay.innerHTML = "";
  if (state.paneID) { overlay.classList.remove("show"); return; }
  const connState = document.getElementById("status").dataset.state;
  const box = document.createElement("div");
  const glyph = document.createElement("div");
  glyph.className = "overlay-glyph";
  glyph.textContent = connState === "connected" ? "▚" : "▚▚";
  const title = document.createElement("div");
  title.className = "overlay-title";
  title.textContent = document.getElementById("status-text").textContent || "Not connected";
  const sub = document.createElement("div");
  sub.className = "overlay-sub";
  sub.textContent = overlaySub(connState);
  box.append(glyph, title, sub);
  overlay.appendChild(box);
  overlay.classList.add("show");
}

function reportError(err) { setStatus(`Error: ${(err && err.message) || "failed"}`, "error"); }

function activatable(el, handler) {
  el.tabIndex = 0;
  el.setAttribute("role", "button");
  el.onclick = handler;
  el.onkeydown = (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    handler();
  };
}

async function boot() {
  const config = await fetch("config.json").then((r) => r.json());
  const url = `ws://${location.hostname}:${config.wsPort}`;
  connect(url);
}

function connect(url) {
  setStatus(`Connecting ${url} …`, "connecting");
  const ws = new WebSocket(url);
  state.ws = ws;
  ws.onopen = () => authenticate();
  ws.onmessage = (e) => onMessage(JSON.parse(e.data));
  ws.onclose = () => {
    rejectPending("Disconnected");
    state.clientID = null;
    state.paneID = null;
    setStatus("Disconnected — retrying in 2s", "error");
    setTimeout(() => connect(url), 2000);
  };
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

function rejectPending(reason) {
  state.pending.forEach((waiter) => waiter.reject({ code: 0, message: reason }));
  state.pending.clear();
}

async function authenticate() {
  const { id, token } = deviceCreds();
  const value = { deviceID: id, deviceName: deviceName(), token, theme: null };
  try {
    const result = await request("authenticateDevice", value);
    onAuthenticated(result).catch(reportError);
  } catch (err) {
    if (err.code === 401) {
      setStatus("Waiting for approval on your Mac …", "connecting");
      try {
        const result = await request("pairDevice", value);
        onAuthenticated(result).catch(reportError);
      } catch (pairErr) {
        setStatus(`Pairing denied (${pairErr.code || "error"})`, "error");
      }
    } else {
      setStatus(`Auth failed (${err.code || "error"})`, "error");
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
  setStatus("Connected", "connected");
  ensureTerminal(pairing);
  state.projects = await request("listProjects");
  renderRail();
  const target = state.projectID || (state.projects[0] && state.projects[0].id);
  if (target) await selectProject(target);
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
      if (data && data.projectID === state.projectID) { state.workspace = data; renderWorkspace(); renderSidebar(); autoAttachFirst(); }
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
  const host = document.createElement("div");
  host.className = "term-host";
  const term = new Terminal({ cursorBlink: true, fontFamily: "SF Mono, Menlo, monospace", fontSize: 13, allowProposedApi: true });
  const fit = new FitAddon.FitAddon();
  term.loadAddon(fit);
  term.open(host);
  term.onData((input) => {
    if (!state.paneID) return;
    request("terminalInput", { paneID: state.paneID, bytes: bytesToBase64(new TextEncoder().encode(input)) });
  });
  window.addEventListener("resize", () => resizePane());
  state.term = term; state.fit = fit; state.termHost = host;
  if (pairing.themeFg !== undefined) applyTheme(pairing.themeFg, pairing.themeBg, pairing.themePalette);
}

function bytesToBase64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 1) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
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
    el.setAttribute("aria-label", project.name);
    activatable(el, () => selectProject(project.id));
    rail.appendChild(el);
  });
}

async function selectProject(projectID) {
  state.projectID = projectID;
  await request("selectProject", { projectID });
  state.worktrees = await request("listWorktrees", { projectID });
  state.worktreeID = state.worktrees[0] ? state.worktrees[0].id : null;
  if (state.worktreeID) await request("selectWorktree", { projectID, worktreeID: state.worktreeID });
  state.workspace = await request("getWorkspace", { projectID });
  renderRail();
  renderSidebar();
  renderWorkspace();
  autoAttachFirst();
}

async function switchWorktree(worktreeID) {
  if (worktreeID === state.worktreeID) return;
  if (state.paneID) {
    try { await request("releasePane", { paneID: state.paneID }); } catch { setStatus("Release failed"); }
    state.paneID = null;
  }
  state.worktreeID = worktreeID;
  await request("selectWorktree", { projectID: state.projectID, worktreeID });
  state.workspace = await request("getWorkspace", { projectID: state.projectID });
  renderSidebar();
  renderWorkspace();
  autoAttachFirst();
}

function sidebarLabel(text) {
  const el = document.createElement("div");
  el.className = "sidebar-label";
  el.textContent = text;
  return el;
}

function renderSidebar() {
  const sidebar = document.getElementById("sidebar");
  sidebar.innerHTML = "";
  const project = state.projects.find((p) => p.id === state.projectID);
  if (!project) return;

  const header = document.createElement("div");
  header.className = "sidebar-header";
  header.textContent = project.name;
  sidebar.appendChild(header);

  if (state.worktrees.length > 1) {
    sidebar.appendChild(sidebarLabel("Worktrees"));
    state.worktrees.forEach((worktree) => {
      const row = document.createElement("div");
      row.className = "sidebar-row" + (worktree.id === state.worktreeID ? " active" : "");
      row.textContent = worktree.name;
      activatable(row, () => switchWorktree(worktree.id));
      sidebar.appendChild(row);
    });
  }

  sidebar.appendChild(sidebarLabel("Sessions"));
  const tabs = state.workspace ? collectTabs(state.workspace.root, []) : [];
  if (!tabs.length) {
    const empty = document.createElement("div");
    empty.className = "sidebar-empty";
    empty.textContent = "No terminal sessions";
    sidebar.appendChild(empty);
    return;
  }
  tabs.forEach((tab) => {
    const row = document.createElement("div");
    row.className = "sidebar-row session" + (tab.paneID === state.paneID ? " active" : "");
    row.textContent = tab.title || "Terminal";
    activatable(row, () => attachPane(tab.paneID));
    sidebar.appendChild(row);
  });
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

function paneExists(node, paneID) {
  if (!node) return false;
  if (node.type === "tabArea") return node.tabArea.tabs.some((tab) => tab.paneID === paneID);
  if (node.type === "split") return paneExists(node.split.first, paneID) || paneExists(node.split.second, paneID);
  return false;
}

function renderWorkspace() {
  const container = document.getElementById("workspace");
  container.innerHTML = "";
  if (!state.workspace) return;
  if (state.paneID && !paneExists(state.workspace.root, state.paneID)) state.paneID = null;
  container.appendChild(buildNode(state.workspace.root));
  placeTerminal();
  resizePane();
  updateOverlay();
}

function buildNode(node) {
  if (node.type === "split") return buildSplit(node.split);
  return buildTabArea(node.tabArea);
}

function buildSplit(split) {
  const el = document.createElement("div");
  el.className = split.direction === "vertical" ? "split vertical" : "split";
  const first = buildNode(split.first);
  const second = buildNode(split.second);
  first.style.flex = `${split.ratio} 1 0`;
  second.style.flex = `${1 - split.ratio} 1 0`;
  el.appendChild(first);
  el.appendChild(second);
  return el;
}

function buildTabArea(area) {
  const el = document.createElement("div");
  el.className = "tabarea";
  const bar = document.createElement("div");
  bar.className = "tabbar";
  area.tabs.forEach((tab) => {
    const isTerminal = tab.kind === "terminal" && Boolean(tab.paneID);
    const t = document.createElement("div");
    t.className = "tab";
    if (isTerminal) t.classList.add("terminal");
    if (tab.id === area.activeTabID) t.classList.add("active");
    if (isTerminal && tab.paneID === state.paneID) t.classList.add("attached");
    t.textContent = tab.title || (isTerminal ? "Terminal" : tab.kind);
    if (isTerminal) activatable(t, () => attachPane(tab.paneID));
    bar.appendChild(t);
  });
  const body = document.createElement("div");
  body.className = "pane-body";
  const activeTab = area.tabs.find((tab) => tab.id === area.activeTabID) || area.tabs[0];
  const activePaneID = activeTab && activeTab.kind === "terminal" ? activeTab.paneID : null;
  body.dataset.pane = activePaneID || "";
  if (!activePaneID) {
    body.appendChild(placeholder(activeTab ? (activeTab.title || activeTab.kind) : "Empty", null));
  } else if (activePaneID !== state.paneID) {
    body.appendChild(placeholder("Click to attach", activePaneID));
  }
  el.appendChild(bar);
  el.appendChild(body);
  return el;
}

function placeholder(text, paneID) {
  const ph = document.createElement("div");
  ph.className = "pane-placeholder";
  ph.textContent = text;
  if (paneID) activatable(ph, () => attachPane(paneID));
  return ph;
}

function placeTerminal() {
  if (!state.paneID || !state.termHost) return;
  document.querySelectorAll(".pane-body").forEach((body) => {
    if (body.dataset.pane === state.paneID) {
      body.innerHTML = "";
      body.appendChild(state.termHost);
    }
  });
}

function autoAttachFirst() {
  if (state.paneID) return;
  const tabs = state.workspace ? collectTabs(state.workspace.root, []) : [];
  if (tabs[0]) attachPane(tabs[0].paneID);
}

async function attachPane(paneID) {
  if (state.paneID === paneID) return;
  if (state.paneID) {
    try { await request("releasePane", { paneID: state.paneID }); } catch { setStatus("Release failed"); }
  }
  state.paneID = paneID;
  state.term.reset();
  renderWorkspace();
  renderSidebar();
  const { cols, rows } = state.term;
  try {
    await request("takeOverPane", { paneID, cols, rows });
    setStatus("Attached", "connected");
  } catch (err) {
    setStatus(`Attach failed (${err.code || "error"})`);
  }
}

function resizePane() {
  if (!state.fit || !state.paneID || !state.termHost || !state.termHost.isConnected) return;
  state.fit.fit();
  const { cols, rows } = state.term;
  request("terminalResize", { paneID: state.paneID, cols, rows });
}

boot();
