'use strict';
/*
 * CV Builder — standalone server (no npm install needed, Node 18+).
 * Serves the app from ./public and stores CVs as JSON files in ./data.
 * Settings come from environment variables or a .env file next to this script:
 *   PORT=3070  HOST=127.0.0.1  DATA_DIR=data  APP_USER=  APP_PASS=
 * If APP_USER and APP_PASS are both set, the whole app is password protected.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = __dirname;

// Minimal .env loader (does not override variables already set)
try {
  for (const line of fs.readFileSync(path.join(ROOT, '.env'), 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^(["'])(.*)\1$/, '$2');
  }
} catch (_) { /* no .env file */ }

const PORT = Number(process.env.PORT) || 3070;
const HOST = process.env.HOST || '127.0.0.1';
const PUBLIC = path.join(ROOT, 'public');
const DATA = path.resolve(ROOT, process.env.DATA_DIR || 'data');
const USER = process.env.APP_USER || '';
const PASS = process.env.APP_PASS || '';
const MAX_BODY = 10 * 1024 * 1024;

fs.mkdirSync(DATA, { recursive: true });

const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.ico': 'image/x-icon', '.webp': 'image/webp', '.txt': 'text/plain; charset=utf-8'
};

const BASE_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'SAMEORIGIN',
  'Referrer-Policy': 'same-origin'
};

function safeEqual(a, b) {
  const x = Buffer.from(String(a)), y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function isAuthed(req) {
  if (!USER || !PASS) return true;
  const h = req.headers.authorization || '';
  if (!h.startsWith('Basic ')) return false;
  const decoded = Buffer.from(h.slice(6), 'base64').toString('utf8');
  const i = decoded.indexOf(':');
  if (i < 0) return false;
  const okUser = safeEqual(decoded.slice(0, i), USER);
  const okPass = safeEqual(decoded.slice(i + 1), PASS);
  return okUser && okPass;
}

function sendJSON(res, code, obj) {
  res.writeHead(code, { ...BASE_HEADERS, 'Content-Type': MIME['.json'], 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(obj));
}

function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    let size = 0; const chunks = [];
    req.on('data', c => {
      size += c.length;
      if (size > limit) { const e = new Error('Body too large'); e.code = 413; reject(e); req.destroy(); return; }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', reject);
  });
}

function listCVs() {
  return fs.readdirSync(DATA)
    .filter(f => f.endsWith('.json'))
    .map(f => {
      try {
        const c = JSON.parse(fs.readFileSync(path.join(DATA, f), 'utf8'));
        return { id: c.id || f.slice(0, -5), title: c.title || 'Untitled CV', updated: c.updated || 0 };
      } catch (_) { return null; }
    })
    .filter(Boolean)
    .sort((a, b) => b.updated - a.updated);
}

function serveStatic(req, res, pathname) {
  let rel;
  try { rel = decodeURIComponent(pathname); } catch (_) { res.writeHead(400, BASE_HEADERS); return res.end('Bad request'); }
  if (rel.endsWith('/')) rel += 'index.html';
  const file = path.join(PUBLIC, path.normalize(rel));
  if (!file.startsWith(PUBLIC + path.sep)) { res.writeHead(403, BASE_HEADERS); return res.end('Forbidden'); }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) { res.writeHead(404, { ...BASE_HEADERS, 'Content-Type': 'text/plain' }); return res.end('Not found'); }
    const ext = path.extname(file).toLowerCase();
    res.writeHead(200, {
      ...BASE_HEADERS,
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Content-Length': st.size,
      'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600'
    });
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(file).pipe(res);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    if (!isAuthed(req)) {
      res.writeHead(401, { ...BASE_HEADERS, 'WWW-Authenticate': 'Basic realm="CV Builder", charset="UTF-8"', 'Content-Type': 'text/plain' });
      return res.end('Sign in required');
    }
    const { pathname } = new URL(req.url, 'http://localhost');

    if (pathname === '/api/health') return sendJSON(res, 200, { ok: true });
    if (pathname === '/api/cvs' && req.method === 'GET') return sendJSON(res, 200, listCVs());

    const m = pathname.match(/^\/api\/cvs\/([A-Za-z0-9_-]{1,64})$/);
    if (m) {
      const file = path.join(DATA, m[1] + '.json');
      if (req.method === 'GET') {
        if (!fs.existsSync(file)) return sendJSON(res, 404, { error: 'CV not found' });
        res.writeHead(200, { ...BASE_HEADERS, 'Content-Type': MIME['.json'], 'Cache-Control': 'no-store' });
        return fs.createReadStream(file).pipe(res);
      }
      if (req.method === 'PUT') {
        const body = await readBody(req, MAX_BODY);
        let data;
        try { data = JSON.parse(body); } catch (_) { return sendJSON(res, 400, { error: 'Invalid JSON' }); }
        if (!data || typeof data !== 'object' || Array.isArray(data)) return sendJSON(res, 400, { error: 'Expected a CV object' });
        data.id = m[1];
        data.updated = Date.now();
        const tmp = `${file}.${process.pid}.tmp`;
        fs.writeFileSync(tmp, JSON.stringify(data));
        fs.renameSync(tmp, file);
        return sendJSON(res, 200, { ok: true, updated: data.updated });
      }
      if (req.method === 'DELETE') {
        fs.rmSync(file, { force: true });
        return sendJSON(res, 200, { ok: true });
      }
      return sendJSON(res, 405, { error: 'Method not allowed' });
    }

    if (pathname.startsWith('/api/')) return sendJSON(res, 404, { error: 'Not found' });
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, BASE_HEADERS); return res.end(); }
    serveStatic(req, res, pathname);
  } catch (err) {
    if (err && err.code === 413) return sendJSON(res, 413, { error: 'CV is too large (10 MB max)' });
    console.error(err);
    if (!res.headersSent) sendJSON(res, 500, { error: 'Server error' });
    else res.end();
  }
});

server.on('error', err => {
  if (err.code === 'EADDRINUSE') console.error(`Port ${PORT} is already in use. Set another port, e.g. PORT=3080 node server.js`);
  else console.error(err);
  process.exit(1);
});

server.listen(PORT, HOST, () => {
  const shown = HOST === '0.0.0.0' ? 'localhost' : HOST;
  console.log(`CV Builder running at http://${shown}:${PORT}`);
  console.log(`Saving CVs to ${DATA}`);
  if (USER && PASS) console.log('Password protection is on.');
});
