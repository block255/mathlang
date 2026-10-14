// ============================================================
// serve_web.js — 极简静态服务器（用于验证 release 构建）
// 用法: node serve_web.js <端口> [目录]      默认目录 = ../app/build/web
// 背景：release 复测不能在 `flutter run` 下做（那是 debug），
//       要用 `flutter build web --release` 产物 + 一个静态服务器。
// ============================================================
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.argv[2] || 57136);
const ROOT = path.resolve(
  process.argv[3] || path.join(__dirname, '..', 'app', 'build', 'web'),
);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream',
  '.map': 'application/json; charset=utf-8',
};

if (!fs.existsSync(path.join(ROOT, 'index.html'))) {
  console.error('找不到 ' + path.join(ROOT, 'index.html') + ' —— 先跑 flutter build web --release');
  process.exit(1);
}

http
  .createServer((req, res) => {
    let p = decodeURIComponent(req.url.split('?')[0]);
    if (p === '/' || p === '') p = '/index.html';
    let file = path.join(ROOT, p);
    if (!file.startsWith(ROOT)) {
      res.writeHead(403);
      res.end('forbidden');
      return;
    }
    if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) {
      file = path.join(ROOT, 'index.html');
    }
    fs.readFile(file, (err, buf) => {
      if (err) {
        res.writeHead(404);
        res.end('not found');
        return;
      }
      res.writeHead(200, {
        'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
        'Cache-Control': 'no-store',
      });
      res.end(buf);
    });
  })
  .listen(PORT, () => console.log('serving ' + ROOT + ' at http://localhost:' + PORT));
