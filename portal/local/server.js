// The portal's local web server: 127.0.0.1 only, Host-checked, static UI plus the shared router.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { createRouter, securityHeaders } from '../core/router.js';

const PUBLIC = new URL('../public/', import.meta.url).pathname;
const FONT = new URL('../../Sources/Zeus/Fonts/PlusJakartaSans.ttf', import.meta.url).pathname;
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.ttf': 'font/ttf', '.ico': 'image/x-icon' };

async function serveStatic(request) {
  const url = new URL(request.url);
  let file = url.pathname === '/' ? path.join(PUBLIC, 'index.html') : path.join(PUBLIC, path.normalize(url.pathname));
  if (url.pathname === '/fonts/PlusJakartaSans.ttf') file = FONT;
  else if (!file.startsWith(PUBLIC)) return new Response('Not found', { status: 404 });
  try {
    const body = fs.readFileSync(file);
    return new Response(body, { headers: { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'cache-control': 'no-cache' } });
  } catch {
    // Single-page app: unknown non-API paths load the shell.
    return new Response(fs.readFileSync(path.join(PUBLIC, 'index.html')), { headers: { 'content-type': TYPES['.html'] } });
  }
}

export function startServer({ portal, secrets, config, port, host = '127.0.0.1' }) {
  const router = createRouter({ portal, secrets, config, serveStatic, publicBase: config.publicBase ?? '' });
  const allowedHosts = new Set([`127.0.0.1:${port}`, `localhost:${port}`]);
  const server = http.createServer(async (req, res) => {
    // DNS-rebinding guard: only answer to our own host names.
    if (!allowedHosts.has(req.headers.host ?? '')) { res.writeHead(421).end('Wrong host'); return; }
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 512 * 1024) { res.writeHead(413).end(); return; }
      chunks.push(chunk);
    }
    const body = ['GET', 'HEAD'].includes(req.method) ? undefined : Buffer.concat(chunks);
    const headers = new Headers();
    for (const [name, value] of Object.entries(req.headers)) {
      if (['host', 'connection', 'content-length', 'transfer-encoding', 'keep-alive'].includes(name)) continue;
      headers.set(name, Array.isArray(value) ? value.join(', ') : value);
    }
    const request = new Request(`http://${req.headers.host}${req.url}`, { method: req.method, headers, body });
    const response = await router.handle(request);
    res.writeHead(response.status, { ...securityHeaders, ...Object.fromEntries(response.headers) });
    res.end(Buffer.from(await response.arrayBuffer()));
  });
  return new Promise((resolve) => server.listen(port, host, () => resolve(server)));
}
