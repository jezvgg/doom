// Клиент: рисует присланные сервером пиксели и отправляет состояние клавиш.
// Никакой игровой логики здесь нет — только websocket, canvas и ввод.

const WIDTH = 128;
const HEIGHT = 128;
const HEADER = 20;                 // x, y, angle, players, время кадра — см. web/world.py
const FRAME_BYTES = HEADER + WIDTH * HEIGHT * 3;
// насколько кадр может отставать от реальности, чтобы его ещё стоило рисовать
const MAX_AGE_MS = 250;

const canvas = document.getElementById("view");
const ctx = canvas.getContext("2d", { alpha: false });
const statusLine = document.getElementById("status");
const statsLine = document.getElementById("stats");
const nameLine = document.getElementById("name");

// один ImageData на всё время жизни: переиспользуем буфер, не мусорим
const image = ctx.createImageData(WIDTH, HEIGHT);
const rgba = image.data;

const KEYMAP = {
  KeyW: "f", ArrowUp: "f",
  KeyS: "b", ArrowDown: "b",
  KeyA: "l", ArrowLeft: "l",
  KeyD: "r", ArrowRight: "r",
};

const held = { f: 0, b: 0, l: 0, r: 0 };
let socket = null;
let lastSent = null;
let reconnectTimer = null;
let frames = 0;
let fps = 0;
let fpsSince = performance.now();
let skipped = 0;                   // кадры из прошлого, которые не рисовали
let dropped = 0;                   // сколько пропущено за последнее окно
let clockOffset = null;            // смещение часов сервера и клиента
let lastX = "-", lastY = "-", lastAngle = "-", lastPlayers = 0;

const playerName = new URLSearchParams(location.search).get("name") || "guest";
nameLine.textContent = "вы: " + playerName;

// --------------------------------------------------------------------------
// ввод
// --------------------------------------------------------------------------

function setKey(key, value) {
  if (held[key] === value) return;
  held[key] = value;
  sendInput();
}

function sendInput() {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  const payload = JSON.stringify(held);
  if (payload === lastSent) return;
  lastSent = payload;
  socket.send(payload);
}

addEventListener("keydown", (event) => {
  const key = KEYMAP[event.code];
  if (!key) return;
  event.preventDefault();
  setKey(key, 1);
});

addEventListener("keyup", (event) => {
  const key = KEYMAP[event.code];
  if (!key) return;
  event.preventDefault();
  setKey(key, 0);
});

// если вкладка потеряла фокус — отпускаем всё, иначе игрок «уезжает»
addEventListener("blur", () => {
  for (const key of Object.keys(held)) held[key] = 0;
  sendInput();
});

// --------------------------------------------------------------------------
// отрисовка
// --------------------------------------------------------------------------

function draw(buffer) {
  if (buffer.byteLength !== FRAME_BYTES) return;

  const view = new DataView(buffer);
  const received = performance.now();

  // Возраст кадра. После обрыва канала буфер выливает пачку «прошлых» кадров:
  // если отставание больше MAX_AGE_MS, кадр не рисуем — иначе картинка едет
  // по истории и догоняет реальность секундами.
  const serverMs = view.getUint32(16, true);
  if (clockOffset === null || received - serverMs < clockOffset) {
    clockOffset = received - serverMs; // смещение часов + минимальная задержка сети
  }
  const age = received - serverMs - clockOffset;
  frames++;
  if (age > MAX_AGE_MS) {
    skipped++;
    updateStats();
    return;
  }

  const x = view.getFloat32(0, true);
  const y = view.getFloat32(4, true);
  const angle = view.getFloat32(8, true);
  const players = view.getUint32(12, true);
  const rgb = new Uint8Array(buffer, HEADER);

  // RGB -> RGBA (ImageData хочет 4 байта на пиксель)
  for (let i = 0, j = 0; i < WIDTH * HEIGHT; i++, j += 3) {
    const out = i << 2;
    rgba[out] = rgb[j];
    rgba[out + 1] = rgb[j + 1];
    rgba[out + 2] = rgb[j + 2];
    rgba[out + 3] = 255;
  }
  ctx.putImageData(image, 0, 0);

  lastX = x.toFixed(2);
  lastY = y.toFixed(2);
  lastAngle = angle.toFixed(2);
  lastPlayers = players;
  updateStats();
}

function updateStats() {
  const now = performance.now();
  if (now - fpsSince >= 500) {
    fps = Math.round((frames * 1000) / (now - fpsSince));
    frames = 0;
    dropped = skipped;
    skipped = 0;
    fpsSince = now;
  }

  statsLine.textContent =
    `x ${lastX} y ${lastY} ∠ ${lastAngle} · ` +
    `игроков ${lastPlayers} · ${fps} fps` +
    (dropped > 0 ? ` · пропущено ${dropped}` : "");
}

// --------------------------------------------------------------------------
// соединение
// --------------------------------------------------------------------------

function setStatus(text, live) {
  statusLine.textContent = text;
  statusLine.classList.toggle("live", Boolean(live));
}

function connect() {
  clearTimeout(reconnectTimer);
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const url = `${proto}://${location.host}/ws?name=${encodeURIComponent(playerName)}`;

  socket = new WebSocket(url);
  socket.binaryType = "arraybuffer";

  socket.onopen = () => {
    setStatus("connected", true);
    lastSent = null;
    sendInput();           // resend: после реконнекта клавиши могут быть зажаты
  };
  socket.onmessage = (event) => {
    if (event.data instanceof ArrayBuffer) draw(event.data);
  };
  socket.onclose = () => {
    setStatus("reconnecting…", false);
    reconnectTimer = setTimeout(connect, 800);
  };
  socket.onerror = () => socket.close();
}

connect();
