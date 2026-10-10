// DeepSeek Harness live wallpaper server.
// Serves the wallpaper video + poster over http://127.0.0.1:8787 for the client plugin.
//
// Video preference: a locally transcoded 1080p60 copy first (far cheaper to decode than a
// 4K/120 fps original: measured 51% dropped frames before vs 4% after), then the original
// workshop file as a fallback. Everything stays on local fixed disks.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { exec } from 'node:child_process';

const HERE = import.meta.dirname || path.dirname(new URL(import.meta.url).pathname);
const CANDIDATES = [
  path.join(HERE, 'assets', 'wallpaper-1080p60.mp4'),   // transcoded: preferred
  path.join(HERE, 'wallpaper.mp4'),                     // generic local copy
  'D:/SteamLibrary/steamapps/workshop/content/431960/3814486439/deepseek-cyberpunk-intro.mp4',
];
const VIDEO = CANDIDATES.find((p) => { try { return fs.existsSync(p); } catch { return false; } });
const POSTERS = [
  path.join(HERE, 'assets', 'wallpaper.webp'),
  path.join(HERE, 'assets', 'poster.jpg'),
  path.join(HERE, 'assets', 'preview.jpg'),
];
const POSTER = POSTERS.find((p) => { try { return fs.existsSync(p); } catch { return false; } });
const PORT = 8787;
const URL = 'http://127.0.0.1:8787/';

if (!VIDEO) {
  console.error('[wallpaper] no video found. looked for:');
  CANDIDATES.forEach((p) => console.error('  - ' + p));
  console.error('[wallpaper] subscribe to the workshop item in Steam, or transcode and drop');
  console.error('[wallpaper] a 1080p copy at assets/wallpaper-1080p60.mp4, then rerun.');
  setTimeout(() => process.exit(1), 8000);
}
console.log('[wallpaper] video: ' + VIDEO);
console.log('[wallpaper] poster: ' + (POSTER || '(none - still frames will be black)'));

const videoBuf = fs.readFileSync(VIDEO);
const posterBuf = fs.existsSync(POSTER) ? fs.readFileSync(POSTER) : null;

const server = http.createServer((req, res) => {
  const path = req.url.split('?')[0];
  if (path === '/wallpaper.mp4') {
    const head = {
      'content-type': 'video/mp4',
      'access-control-allow-origin': '*',
      'cache-control': 'public, max-age=3600',
      'accept-ranges': 'bytes',
    };
    const range = req.headers.range;
    if (range) {
      const m = /bytes=(\d*)-(\d*)/.exec(range);
      const start = m && m[1] ? Number(m[1]) : 0;
      const end = m && m[2] ? Number(m[2]) : videoBuf.length - 1;
      res.writeHead(206, { ...head, 'content-range': 'bytes ' + start + '-' + end + '/' + videoBuf.length, 'content-length': end - start + 1 });
      res.end(videoBuf.subarray(start, end + 1));
    } else {
      res.writeHead(200, { ...head, 'content-length': videoBuf.length });
      res.end(videoBuf);
    }
    return;
  }
  if (path === '/wallpaper.webp' && posterBuf) {
    res.writeHead(200, { 'content-type': 'image/webp', 'access-control-allow-origin': '*', 'cache-control': 'public, max-age=3600' });
    res.end(posterBuf);
    return;
  }
  res.writeHead(404, { 'content-type': 'text/plain' });
  res.end('not found');
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.log('[wallpaper] port ' + PORT + ' is already in use - the wallpaper server is probably already running.');
    setTimeout(() => process.exit(0), 4000);
  } else {
    console.error('[wallpaper] server error: ' + err.message);
    setTimeout(() => process.exit(1), 6000);
  }
});

server.listen(PORT, '127.0.0.1', () => {
  console.log('');
  console.log('  DeepSeek Harness live wallpaper server');
  console.log('  serving: ' + VIDEO);
  console.log('  address: ' + URL);
  console.log('');
  console.log('  keep this window open (minimized is fine).');
  console.log('  press Ctrl+C to stop.');
  console.log('');
  if (process.argv.includes('--open')) exec('start "" ' + URL);
});
