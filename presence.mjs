#!/usr/bin/env node
// Discord Rich Presence per le sessioni Claude Code.
// Mostra sul TUO profilo Discord quante sessioni Claude stai spinnando sul Mac.
// Zero dipendenze: parla direttamente con l'app Discord via socket IPC.
//
// Config: CLIENT_ID via env DISCORD_CLIENT_ID (Application ID dal Developer Portal)
//         oppure file ./config.json { "clientId": "..." }.
//
// Protocollo IPC Discord:
//   socket  $TMPDIR/discord-ipc-0  (unix domain)
//   frame   [op:uint32 LE][len:uint32 LE][json utf8]
//   op 0 = HANDSHAKE  {v:1, client_id}
//   op 1 = FRAME      {cmd:"SET_ACTIVITY", args:{pid, activity}, nonce}
//   op 2 = CLOSE      op 3/4 = PING/PONG

import net from "node:net";
import os from "node:os";
import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// --- config ---------------------------------------------------------------
function loadClientId() {
  if (process.env.DISCORD_CLIENT_ID) return process.env.DISCORD_CLIENT_ID.trim();
  try {
    const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, "config.json"), "utf8"));
    if (cfg.clientId) return String(cfg.clientId).trim();
  } catch {}
  return null;
}
const CLIENT_ID = loadClientId();
if (!CLIENT_ID) {
  console.error("[presence] manca DISCORD_CLIENT_ID (env o config.json). Esco.");
  process.exit(1);
}
const COUNT_SCRIPT = path.join(__dirname, "count-sessions.sh");
const REFRESH_MS = Number(process.env.REFRESH_MS || 15000);
// art-asset key oppure URL diretto immagine (test client-side resolve)
let LARGE_IMAGE = process.env.LARGE_IMAGE || "";
try {
  const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, "config.json"), "utf8"));
  if (!LARGE_IMAGE && cfg.largeImage) LARGE_IMAGE = String(cfg.largeImage);
} catch {}
const START_TS = Date.now();

// --- IPC socket path -------------------------------------------------------
function ipcPath(i = 0) {
  const base =
    process.env.XDG_RUNTIME_DIR ||
    process.env.TMPDIR ||
    process.env.TMP ||
    process.env.TEMP ||
    os.tmpdir();
  return path.join(base.replace(/\/$/, ""), `discord-ipc-${i}`);
}

// --- frame encoding --------------------------------------------------------
function encode(op, payload) {
  const data = Buffer.from(JSON.stringify(payload), "utf8");
  const head = Buffer.alloc(8);
  head.writeUInt32LE(op, 0);
  head.writeUInt32LE(data.length, 4);
  return Buffer.concat([head, data]);
}

let nonceSeq = 0;
function nonce() {
  return `${START_TS}-${nonceSeq++}`;
}

// --- session count ---------------------------------------------------------
// count-sessions.sh stampa "<aperte> <al_lavoro>"
function getCount() {
  return new Promise((resolve) => {
    execFile("/bin/bash", [COUNT_SCRIPT], { timeout: 6000 }, (err, stdout) => {
      if (err) return resolve({ open: 0, working: 0 });
      const [open, working] = String(stdout).trim().split(/\s+/).map((n) => parseInt(n, 10) || 0);
      resolve({ open: open || 0, working: working || 0 });
    });
  });
}

// --- presence connection ---------------------------------------------------
let sock = null;
let connected = false;
let recvBuf = Buffer.alloc(0);
let lastKey = "";

function setActivity({ open, working }) {
  if (!connected) return;
  // 0 aperte -> presence "vuota" (clear) cosi non resta appeso se chiudi tutto
  const activity =
    open === 0
      ? null
      : {
          details:
            working > 0
              ? `${working} al lavoro · ${open} apert${open === 1 ? "a" : "e"}`
              : `${open} session${open === 1 ? "e" : "i"} apert${open === 1 ? "a" : "e"} (idle)`,
          state: working > 0 ? "🟢 Claude Code in esecuzione" : "Claude Code",
          timestamps: { start: Math.floor(START_TS / 1000) },
          // LARGE_IMAGE: art-asset key OPPURE (su client recenti) URL diretto.
          ...(LARGE_IMAGE
            ? { assets: { large_image: LARGE_IMAGE, large_text: "Claude Code" } }
            : {}),
        };
  sock.write(
    encode(1, {
      cmd: "SET_ACTIVITY",
      args: { pid: process.pid, activity },
      nonce: nonce(),
    })
  );
}

async function tick() {
  const c = await getCount();
  const key = `${c.open}/${c.working}`;
  if (key !== lastKey) {
    lastKey = key;
    setActivity(c);
    console.error(`[presence] ${new Date().toISOString()} -> ${c.open} aperte, ${c.working} al lavoro`);
  }
}

function connect() {
  const p = ipcPath(0);
  if (!fs.existsSync(p)) {
    console.error(`[presence] socket non trovato (${p}). Discord aperto? riprovo tra 10s`);
    return setTimeout(connect, 10000);
  }
  sock = net.createConnection(p);
  recvBuf = Buffer.alloc(0);

  sock.on("connect", () => {
    sock.write(encode(0, { v: 1, client_id: CLIENT_ID }));
  });

  sock.on("data", (chunk) => {
    recvBuf = Buffer.concat([recvBuf, chunk]);
    while (recvBuf.length >= 8) {
      const op = recvBuf.readUInt32LE(0);
      const len = recvBuf.readUInt32LE(4);
      if (recvBuf.length < 8 + len) break;
      const body = recvBuf.slice(8, 8 + len).toString("utf8");
      recvBuf = recvBuf.slice(8 + len);
      let msg = {};
      try { msg = JSON.parse(body); } catch {}
      if (op === 1 && msg.evt === "READY") {
        connected = true;
        console.error(`[presence] connesso come app ${CLIENT_ID} (user: ${msg?.data?.user?.username || "?"})`);
        lastKey = "";
        tick();
      } else if (op === 2) {
        console.error(`[presence] Discord CLOSE: ${body}`);
      } else if (op === 1 && msg.evt === "ERROR") {
        console.error(`[presence] Discord ERROR: ${body}`);
      }
    }
  });

  const onGone = (why) => {
    if (connected || sock) console.error(`[presence] disconnesso (${why}), riconnetto tra 10s`);
    connected = false;
    sock = null;
    setTimeout(connect, 10000);
  };
  sock.on("error", (e) => onGone(e.code || e.message));
  sock.on("end", () => onGone("end"));
  sock.on("close", () => onGone("close"));
}

connect();
setInterval(tick, REFRESH_MS);

process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
