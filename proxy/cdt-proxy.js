// Proxy local que agrega el tema a claude.ai para Claude Desktop, sin modificar la app.
//
// - Escucha solo en 127.0.0.1. Sirve /proxy.pac, que manda a este proxy SOLO claude.ai.
// - Para claude.ai termina TLS con el certificado local (ver gen-cert.sh), reenvía cada pedido
//   a claude.ai real y, en las páginas HTML, agrega <style id="cdt-theme"> antes de </head>.
//   Todo lo demás (JS, CSS, API, streaming, WebSockets) pasa sin cambios.
// - Rechaza cualquier otro destino: no es un proxy general.
// - No guarda contenido de las páginas ni pedidos; el log solo registra arranque, inyecciones y errores.
//
// Uso: node cdt-proxy.js        (config: CDT_PORT, CDT_DIR; por defecto 8737 y ~/.claude/desktop-themes)
"use strict";
const http = require("http");
const https = require("https");
const tls = require("tls");
const fs = require("fs");
const path = require("path");
const os = require("os");
const zlib = require("zlib");
const { themeToCss } = require("./theme-json");

const HOST = "claude.ai";
const PORT = Number(process.env.CDT_PORT || 8737);
const DIR = process.env.CDT_DIR || path.join(os.homedir(), ".claude", "desktop-themes");
const TLS_DIR = path.join(DIR, "tls");
const LOG = path.join(DIR, "proxy.log");
const HOP = new Set(["connection", "keep-alive", "proxy-connection", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade"]);

function log(msg) {
  try {
    if (fs.existsSync(LOG) && fs.statSync(LOG).size > 512 * 1024) fs.renameSync(LOG, LOG + ".1");
    fs.appendFileSync(LOG, `${new Date().toISOString()} ${msg}\n`);
  } catch {}
}

// Tema activo: ~/.claude/desktop-themes/active tiene el nombre; <nombre>.json el tema. Se relee si cambia.
let cache = { key: "", css: null, name: null };
function currentTheme() {
  try {
    const name = fs.readFileSync(path.join(DIR, "active"), "utf8").trim();
    if (!name || name === "none" || !/^[\w-]+$/.test(name)) return { css: null, name: null };
    const file = path.join(DIR, name + ".json");
    const key = `${name}:${fs.statSync(file).mtimeMs}`;
    if (cache.key !== key) cache = { key, name, css: themeToCss(JSON.parse(fs.readFileSync(file, "utf8"))) };
    return cache;
  } catch (e) {
    if (e.code !== "ENOENT") log(`tema inválido: ${e.message}`);
    return { css: null, name: null };
  }
}

const PAC = `function FindProxyForURL(url, host) {
  if (host === "${HOST}") return "PROXY 127.0.0.1:${PORT}; DIRECT";
  return "DIRECT";
}
`;

const upstreamAgent = new https.Agent({ keepAlive: true, maxSockets: 64 });

function forwardHeaders(h) {
  const out = {};
  for (const [k, v] of Object.entries(h)) if (!HOP.has(k.toLowerCase())) out[k] = v;
  out.host = HOST;
  return out;
}

function decode(buf, enc) {
  switch ((enc || "identity").toLowerCase()) {
    case "identity": return buf;
    case "gzip": case "x-gzip": return zlib.gunzipSync(buf);
    case "deflate": return zlib.inflateSync(buf);
    case "br": return zlib.brotliDecompressSync(buf);
    default: return null; // codificación que no sabemos leer: se pasa sin tema
  }
}

function inject(html, css, name) {
  const tag = `<style id="cdt-theme" data-theme="${name}">\n${css}</style>`;
  const i = html.search(/<\/head>/i);
  return i >= 0 ? html.slice(0, i) + tag + html.slice(i) : tag + html;
}

// Atiende los pedidos HTTP descifrados que llegan por el túnel de claude.ai
function handleMitm(req, res) {
  const headers = forwardHeaders(req.headers);
  headers["accept-encoding"] = "gzip, deflate, br";
  const isDoc = ["document", "iframe"].includes(String(req.headers["sec-fetch-dest"] || ""));
  if (isDoc) { delete headers["if-none-match"]; delete headers["if-modified-since"]; }

  const up = https.request({ host: HOST, servername: HOST, port: 443, method: req.method, path: req.url, headers, agent: upstreamAgent }, (ur) => {
    const type = String(ur.headers["content-type"] || "");
    const theme = isDoc && ur.statusCode === 200 && type.includes("text/html") ? currentTheme() : null;
    const outHeaders = {};
    for (const [k, v] of Object.entries(ur.headers)) if (!HOP.has(k)) outHeaders[k] = v;

    if (!theme || !theme.css) {
      res.writeHead(ur.statusCode, ur.statusMessage, outHeaders);
      ur.pipe(res);
      return;
    }
    const chunks = [];
    ur.on("data", (c) => chunks.push(c));
    ur.on("end", () => {
      const raw = Buffer.concat(chunks);
      let body;
      try { body = decode(raw, ur.headers["content-encoding"]); } catch (e) { log(`no pude descomprimir ${req.url}: ${e.message}`); }
      if (!body) {
        res.writeHead(ur.statusCode, ur.statusMessage, outHeaders);
        return res.end(raw);
      }
      const out = Buffer.from(inject(body.toString("utf8"), theme.css, theme.name), "utf8");
      delete outHeaders["content-encoding"];
      delete outHeaders["etag"];
      outHeaders["content-length"] = out.length;
      res.writeHead(ur.statusCode, ur.statusMessage, outHeaders);
      res.end(out);
      log(`tema "${theme.name}" → ${req.url.split("?")[0]}`);
    });
    ur.on("error", (e) => { log(`error leyendo ${req.url}: ${e.message}`); res.destroy(); });
  });
  up.on("error", (e) => {
    log(`error hacia ${HOST}${req.url.split("?")[0]}: ${e.message}`);
    if (!res.headersSent) { res.writeHead(502, { "content-type": "text/plain" }); res.end("cdt-proxy: " + e.message); }
    else res.destroy();
  });
  req.pipe(up);
}

// WebSockets y otros upgrades: se reenvían en crudo
function handleMitmUpgrade(req, socket, head) {
  const up = tls.connect({ host: HOST, port: 443, servername: HOST, ALPNProtocols: ["http/1.1"] }, () => {
    let raw = `${req.method} ${req.url} HTTP/1.1\r\n`;
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      raw += `${k}: ${k.toLowerCase() === "host" ? HOST : req.rawHeaders[i + 1]}\r\n`;
    }
    up.write(raw + "\r\n");
    if (head && head.length) up.write(head);
    socket.pipe(up).pipe(socket);
  });
  const close = () => { socket.destroy(); up.destroy(); };
  up.on("error", (e) => { log(`upgrade error: ${e.message}`); close(); });
  socket.on("error", close);
}

function loadTls() {
  const pfx = path.join(TLS_DIR, "claude.ai.pfx"); // Windows: lo genera New-SelfSignedCertificate
  if (fs.existsSync(pfx)) {
    return tls.createSecureContext({ pfx: fs.readFileSync(pfx), passphrase: fs.readFileSync(path.join(TLS_DIR, "pfx.pass"), "utf8").trim() });
  }
  return tls.createSecureContext({
    key: fs.readFileSync(path.join(TLS_DIR, "claude.ai.key")),
    cert: fs.readFileSync(path.join(TLS_DIR, "claude.ai.crt")),
  });
}

function main() {
  let ctx;
  try { ctx = loadTls(); } catch (e) { console.error(`Falta el certificado en ${TLS_DIR}: ${e.message}`); process.exit(1); }

  const mitm = http.createServer(handleMitm);
  mitm.on("upgrade", handleMitmUpgrade);
  mitm.on("clientError", (e, s) => s.destroy());
  mitm.keepAliveTimeout = 60000;

  const server = http.createServer((req, res) => {
    const url = req.url || "/";
    if (url === "/proxy.pac") {
      res.writeHead(200, { "content-type": "application/x-ns-proxy-autoconfig", "cache-control": "no-store" });
      return res.end(PAC);
    }
    if (url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      return res.end(JSON.stringify({ ok: true, theme: currentTheme().name, pid: process.pid }));
    }
    if (url.startsWith(`http://${HOST}/`) || url === `http://${HOST}`) {
      res.writeHead(301, { location: url.replace(/^http:/, "https:") });
      return res.end();
    }
    res.writeHead(403, { "content-type": "text/plain" });
    res.end("cdt-proxy: solo atiende claude.ai\n");
  });

  server.on("connect", (req, client, head) => {
    const [host, port] = String(req.url).split(":");
    if (host !== HOST || port !== "443") {
      client.end("HTTP/1.1 403 Forbidden\r\n\r\n");
      return;
    }
    client.write("HTTP/1.1 200 Connection Established\r\n\r\n");
    if (head && head.length) client.unshift(head);
    const secure = new tls.TLSSocket(client, { isServer: true, secureContext: ctx, ALPNProtocols: ["http/1.1"] });
    secure.on("error", () => client.destroy());
    client.on("error", () => secure.destroy());
    mitm.emit("connection", secure);
  });

  server.on("clientError", (e, s) => s.destroy());
  server.listen(PORT, "127.0.0.1", () => {
    log(`escuchando en 127.0.0.1:${PORT} (tema: ${currentTheme().name || "ninguno"})`);
    console.log(`cdt-proxy en 127.0.0.1:${PORT}`);
  });
  server.on("error", (e) => { console.error(e.message); log(`no pude escuchar: ${e.message}`); process.exit(1); });

  // Si el certificado cambia (reinstalación), recargarlo sin reiniciar
  fs.watchFile(path.join(TLS_DIR, "claude.ai.crt"), { interval: 5000 }, () => {
    try { ctx = loadTls(); log("certificado recargado"); } catch (e) { log(`no pude recargar el certificado: ${e.message}`); }
  });
}

if (require.main === module) main();
else module.exports = { inject, decode, PAC }; // para pruebas
