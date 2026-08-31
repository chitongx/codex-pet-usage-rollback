"use strict";

const { app, BrowserWindow, TouchBar, nativeImage } = require("electron");
const { spawn } = require("node:child_process");
const path = require("node:path");

const { TouchBarButton, TouchBarSpacer } = TouchBar;
const WINDOWS = new Map();
const REFRESH_MS = 60 * 1000;
const REQUEST_TIMEOUT_MS = 8 * 1000;
const CODEX_PATH = path.join(process.resourcesPath, "codex");
const REM_PATH = path.join(process.resourcesPath, "codex-rem.png");

let usage = { fiveHour: null, weekly: null };
let refreshing = false;

function remIcon() {
  try {
    return nativeImage.createFromPath(REM_PATH).resize({ width: 28, height: 28 });
  } catch (_) {
    return nativeImage.createEmpty();
  }
}

function colorFor(remaining) {
  if (remaining == null) return "#4a4a4a";
  if (remaining <= 20) return "#9b3d45";
  if (remaining <= 50) return "#9b6a2d";
  return "#2e7654";
}

function makeBar() {
  const rem = new TouchBarButton({
    label: "",
    accessibilityLabel: "雷姆",
    backgroundColor: "#282828"
  });
  rem.icon = remIcon();
  rem.iconPosition = "overlay";

  const fiveHour = new TouchBarButton({
    label: "5小时 --",
    accessibilityLabel: "Codex 5 小时剩余额度",
    backgroundColor: colorFor(null)
  });
  const weekly = new TouchBarButton({
    label: "每周 --",
    accessibilityLabel: "Codex 每周剩余额度",
    backgroundColor: colorFor(null)
  });
  const bar = new TouchBar({
    items: [
      rem,
      new TouchBarSpacer({ size: "small" }),
      fiveHour,
      new TouchBarSpacer({ size: "small" }),
      weekly
    ]
  });
  return { bar, fiveHour, weekly };
}

function updateItem(item, title, value) {
  item.label = `${title} ${value == null ? "--" : `${value}%`}`;
  item.backgroundColor = colorFor(value);
}

function updateBars() {
  for (const state of WINDOWS.values()) {
    updateItem(state.fiveHour, "5小时", usage.fiveHour);
    updateItem(state.weekly, "每周", usage.weekly);
  }
}

function attachWindow(window) {
  const state = makeBar();
  WINDOWS.set(window.webContents.id, state);
  updateBars();
  try {
    window.setTouchBar(state.bar);
  } catch (_) {
    WINDOWS.delete(window.webContents.id);
  }
  window.once("closed", () => WINDOWS.delete(window.webContents.id));
}

function number(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function remaining(window) {
  const used = number(window && window.usedPercent);
  if (used == null) return null;
  return Math.max(0, Math.min(100, Math.round(100 - used)));
}

function refreshUsage() {
  if (refreshing || !app.isPackaged) return;
  refreshing = true;
  const child = spawn(CODEX_PATH, ["-s", "read-only", "-a", "never", "app-server"], {
    stdio: ["pipe", "pipe", "ignore"]
  });
  let buffer = "";
  let finished = false;
  const timeout = setTimeout(() => finish(null), REQUEST_TIMEOUT_MS);

  function finish(result) {
    if (finished) return;
    finished = true;
    clearTimeout(timeout);
    child.stdout.removeAllListeners("data");
    child.removeAllListeners("error");
    if (child.exitCode == null) child.kill();
    refreshing = false;
    if (result) {
      usage = result;
      updateBars();
    }
  }

  child.stdout.on("data", (chunk) => {
    buffer += chunk.toString();
    let newline;
    while ((newline = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, newline).trim();
      buffer = buffer.slice(newline + 1);
      if (!line) continue;
      let message;
      try {
        message = JSON.parse(line);
      } catch (_) {
        continue;
      }
      if (message.id !== 2 || !message.result) continue;
      const limits = message.result.rateLimits || {};
      finish({
        fiveHour: remaining(limits.primary),
        weekly: remaining(limits.secondary)
      });
      return;
    }
  });
  child.once("error", () => finish(null));

  const initialize =
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codex-touchbar","version":"1.0.0"}}}\n';
  const request =
    '{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":{}}\n';
  child.stdin.write(initialize + request);
}

if (process.platform === "darwin") {
  app.on("browser-window-created", (_event, window) => attachWindow(window));
  app.whenReady().then(() => {
    for (const window of BrowserWindow.getAllWindows()) attachWindow(window);
    refreshUsage();
    setInterval(refreshUsage, REFRESH_MS);
  });
}

