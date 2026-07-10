const state = {
  ws: null, clientID: null, reqId: 0, pending: new Map(),
  projects: [], projectID: null, worktreeID: null, workspace: null,
  paneID: null, term: null, fit: null,
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
  ws.onclose = () => {
    rejectPending("Disconnected");
    state.clientID = null;
    state.paneID = null;
    setStatus("Disconnected — retrying in 2s");
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
  if (state.projectID) await selectProject(state.projectID);
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
    request("terminalInput", { paneID: state.paneID, bytes: bytesToBase64(new TextEncoder().encode(input)) });
  });
  window.addEventListener("resize", () => resizePane());
  state.term = term; state.fit = fit;
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
