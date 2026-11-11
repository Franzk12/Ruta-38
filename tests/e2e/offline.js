// Prueba del service worker (sw.js): la app abre sin internet y, con internet, siempre
// toma la versión publicada. Usa una copia temporal del proyecto y Supabase simulado.
// Uso: node tests/e2e/offline.js
const http = require('http'), fs = require('fs'), path = require('path'), os = require('os');
const { chromium } = require('playwright');

const RAIZ = path.join(__dirname, '..', '..');
const TMP = fs.mkdtempSync(path.join(os.tmpdir(), 'rpos-'));
for (const f of ['index.html', 'sw.js', 'manifest.webmanifest']) fs.copyFileSync(path.join(RAIZ, f), path.join(TMP, f));
for (const d of ['icons', 'vendor']) fs.cpSync(path.join(RAIZ, d), path.join(TMP, d), { recursive: true });

const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.webmanifest': 'application/manifest+json', '.png': 'image/png' };
let caido = false;
const servidor = http.createServer((req, res) => {
  if (caido) return req.socket.destroy();                 // "sin internet": corta la conexión
  let ruta = decodeURIComponent(req.url.split('?')[0]);
  if (ruta === '/') ruta = '/index.html';
  const archivo = path.join(TMP, ruta);
  if (!archivo.startsWith(TMP) || !fs.existsSync(archivo) || fs.statSync(archivo).isDirectory()) { res.writeHead(404); return res.end('no'); }
  res.writeHead(200, { 'Content-Type': TIPOS[path.extname(archivo)] || 'application/octet-stream', 'Cache-Control': 'no-cache' });
  fs.createReadStream(archivo).pipe(res);
});

let fallas = 0;
function ok(cond, msg) { if (cond) console.log('ok   ' + msg); else { fallas++; console.log('FALLÓ ' + msg); } }

(async () => {
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  const URL_APP = 'http://127.0.0.1:' + servidor.address().port + '/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext();
  await ctx.route(u => !u.href.startsWith(URL_APP), route => {
    const u = new URL(route.request().url());
    if (!u.hostname.endsWith('.supabase.co')) return route.abort();
    if (u.pathname === '/auth/v1/token') return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ access_token: 't', refresh_token: 'r', expires_in: 3600, user: { email: 'caja@prueba.test' } }) });
    return route.fulfill({ status: 200, contentType: 'application/json', body: '[]' });
  });
  const page = await ctx.newPage();
  page.on('pageerror', e => { fallas++; console.log('FALLÓ error de JavaScript: ' + e.message); });

  await page.goto(URL_APP);
  await page.evaluate(() => navigator.serviceWorker.ready);
  await page.waitForFunction(() => !!navigator.serviceWorker.controller, null, { timeout: 10000 }).catch(() => { });
  ok(await page.evaluate(() => !!navigator.serviceWorker.controller), 'el service worker queda instalado y a cargo de la página');
  ok(await page.evaluate(async () => { const r = await fetch('manifest.webmanifest'); const m = await r.json(); return m.icons.length === 2 && m.display === 'standalone'; }), 'el manifiesto de app instalable es válido');

  caido = true;
  await page.reload();
  ok(await page.title() === 'Ruta 38 Repuestos' && await page.isVisible('#login-screen'), 'sin internet la app abre igual (recarga)');
  const otra = await ctx.newPage();
  await otra.goto(URL_APP);
  ok(await otra.title() === 'Ruta 38 Repuestos', 'sin internet la app abre en una pestaña nueva');
  ok(await otra.evaluate(() => cargarXLSX().then(X => typeof X.read === 'function')), 'sin internet funciona el lector de Excel del importador');
  ok(await otra.evaluate(() => fetch('icons/icono-192.png').then(r => r.ok)), 'sin internet están los íconos');
  await otra.close();

  // Se publica una versión nueva: con internet tiene que verse en la primera recarga
  caido = false;
  const html = fs.readFileSync(path.join(TMP, 'index.html'), 'utf8').replace('<title>Ruta 38 Repuestos</title>', '<title>Ruta 38 Repuestos v-nueva</title>');
  fs.writeFileSync(path.join(TMP, 'index.html'), html);
  await page.reload();
  ok(await page.title() === 'Ruta 38 Repuestos v-nueva', 'con internet, una versión nueva se ve en la primera recarga (no queda la vieja)');
  caido = true;
  await page.reload();
  ok(await page.title() === 'Ruta 38 Repuestos v-nueva', 'y la copia sin internet pasa a ser la versión nueva');

  await browser.close(); servidor.close();
  fs.rmSync(TMP, { recursive: true, force: true });
  console.log(fallas ? '\n' + fallas + ' PRUEBA(S) FALLARON' : '\nPRUEBAS SIN CONEXIÓN: TODO OK');
  process.exit(fallas ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
