// Prueba de punta a punta de index.html en un navegador real (Chromium, vía Playwright),
// con Supabase SIMULADO: ningún pedido sale a la base real.
// Uso: node tests/e2e/smoke.js
const http = require('http'), fs = require('fs'), path = require('path');
const { chromium } = require('playwright');

const RAIZ = process.env.RPOS_RAIZ || path.join(__dirname, '..', '..');
const TIPOS = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png' };
const servidor = http.createServer((req, res) => {
  let ruta = decodeURIComponent(req.url.split('?')[0]);
  if (ruta === '/') ruta = '/index.html';
  const archivo = path.join(RAIZ, ruta);
  if (!archivo.startsWith(RAIZ) || !fs.existsSync(archivo) || fs.statSync(archivo).isDirectory()) { res.writeHead(404); return res.end('no'); }
  res.writeHead(200, { 'Content-Type': TIPOS[path.extname(archivo)] || 'application/octet-stream' });
  fs.createReadStream(archivo).pipe(res);
});

let fallas = 0;
function ok(cond, msg) { if (cond) console.log('ok   ' + msg); else { fallas++; console.log('FALLÓ ' + msg); } }
const espera = ms => new Promise(r => setTimeout(r, ms));
async function hasta(fn, msg, ms = 8000) {
  const fin = Date.now() + ms;
  while (Date.now() < fin) { if (await fn()) return true; await espera(50); }
  console.log('     (se agotó la espera: ' + msg + ')'); return false;
}

(async () => {
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  const URL_APP = 'http://127.0.0.1:' + servidor.address().port + '/';
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ serviceWorkers: 'block' });
  const page = await ctx.newPage();
  page.on('dialog', d => d.accept());
  page.on('pageerror', e => { fallas++; console.log('FALLÓ error de JavaScript en la página: ' + e.message); });

  // ── Supabase simulado ──
  const base = { modo: 'ok', ventas: [], recibidas: [], proxId: 101, rechazarUid: null };
  await ctx.route('**/*', async route => {
    const req = route.request(), u = new URL(req.url());
    if (u.origin === new URL(URL_APP).origin) return route.continue();
    if (!u.hostname.endsWith('.supabase.co')) return route.abort();   // fuentes, CDN: afuera
    const json = (status, body) => route.fulfill({ status, contentType: 'application/json', body: JSON.stringify(body) });
    if (u.pathname === '/auth/v1/token') return json(200, { access_token: 'tok', refresh_token: 'ref', expires_in: 3600, user: { email: 'caja@prueba.test' } });
    if (u.pathname === '/rest/v1/productos' && req.method() === 'GET') return json(200, [
      { id: 1, codigo: '111', nombre: 'Filtro de aceite', categoria: 'Motor', marca: '', precio: 1000, costo: 600, stock: 10, stockDeposito: 5, minStock: 1, activos: true },
      { id: 2, codigo: '222', nombre: 'Bujía', categoria: 'Motor', marca: '', precio: 250.5, costo: 100, stock: 3, stockDeposito: 0, minStock: 0, activos: true }]);
    if (u.pathname === '/rest/v1/ventas') return json(200, []);
    if (u.pathname === '/rest/v1/categorias' || u.pathname === '/rest/v1/marcas') return json(200, []);
    if (u.pathname === '/rest/v1/rpc/registrar_venta') {
      const cuerpo = JSON.parse(req.postData());
      if (base.modo === 'caida') return route.abort('internetdisconnected');
      if (base.modo === 'colgada') return;                              // nunca contesta
      if (base.modo === 'lenta') await espera(700);
      base.recibidas.push(cuerpo);
      if (cuerpo.p_venta.uid === base.rechazarUid) return json(400, { code: 'P0001', message: 'La venta tiene un item con cantidad o precio inválido' });
      let v = base.ventas.find(x => x.uid === cuerpo.p_venta.uid);
      if (!v) { v = { id: base.proxId++, uid: cuerpo.p_venta.uid, anulada: !!cuerpo.p_venta.anulada }; base.ventas.push(v); }
      else if (cuerpo.p_venta.anulada) v.anulada = true;
      return json(200, { venta_id: v.id, stocks: [] });
    }
    return json(404, { message: 'ruta no simulada: ' + u.pathname });
  });

  const cola = () => page.evaluate(() => JSON.parse(localStorage.getItem('rpos_pending_ventas') || '[]'));
  const rechazadas = () => page.evaluate(() => JSON.parse(localStorage.getItem('rpos_rejected_ventas') || '[]'));
  // Cobra una venta de 1 unidad del producto dado, pagando con débito (no pide efectivo)
  const cobrar = (idProd, esperar = true) => page.evaluate(async ([id, esperar]) => {
    agregarAlCarro(productos.find(p => String(p.id) === String(id)));
    document.getElementById('metodo-pago').value = 'debito';
    const p = cobrar();
    if (esperar) await p;
    return historial[0].uid;
  }, [idProd, esperar]);

  // 1) Login
  await page.goto(URL_APP);
  ok(await page.isVisible('#login-screen:not(.hidden)'), 'sin sesión se muestra el login');
  await page.fill('#login-email', 'caja@prueba.test');
  await page.fill('#login-pass', 'secreto');
  await page.click('#login-btn');
  ok(await hasta(() => page.evaluate(() => productos.length === 2), 'productos cargados'), 'después del login se cargan los productos');

  // 2) Venta con conexión
  let uid1 = await cobrar(1);
  ok(base.recibidas.length === 1 && base.recibidas[0].p_venta.uid === uid1, 'venta online: llega a la base');
  ok((await cola()).length === 0, 'venta online: la cola queda vacía al confirmar la base');
  ok(await page.evaluate(() => historial[0].dbId === 101 && historial[0].pendiente === false), 'venta online: el historial toma el número definitivo');
  ok(await page.evaluate(() => productos.find(p => p.id == 1).stock === 9), 'venta online: descuenta stock local');
  await page.evaluate(() => { var o = document.querySelector('.overlay:not(.hidden)'); if (o) o.classList.add('hidden'); });

  // 3) Dos ventas sin conexión, después vuelve internet
  base.modo = 'caida';
  const uid2 = await cobrar(1), uid3 = await cobrar(2);
  ok((await cola()).map(v => v.uid).join() === [uid2, uid3].join(), 'sin conexión: las dos ventas quedan en la cola, en orden');
  ok(await page.evaluate(() => nroComprobante(historial[0]).startsWith('P-')), 'sin conexión: número provisorio P-');
  base.modo = 'ok';
  await page.evaluate(() => flushPendingVentas());
  ok((await cola()).length === 0, 'al volver internet la cola se vacía');
  ok(base.ventas.length === 3, 'al volver internet las ventas llegan una sola vez cada una');

  // 4) La venta queda anotada ANTES de enviarse: se cierra la pestaña a mitad del envío
  base.modo = 'colgada';
  const uid4 = await cobrar(1, false);
  ok((await cola()).some(v => v.uid === uid4), 'la venta está en la cola aunque la base todavía no contestó');
  base.modo = 'ok';
  await page.reload();
  ok(await hasta(() => base.ventas.some(v => v.uid === uid4), 'reenvío tras recargar'), 'tras cerrar y reabrir, la venta en vuelo se envía sola');
  ok(await hasta(async () => (await cola()).length === 0, 'cola vacía'), 'y la cola queda vacía');

  // 5) Una venta rechazada por la base no traba a las que vienen detrás
  base.modo = 'caida';
  const uid5 = await cobrar(1), uid6 = await cobrar(2);
  base.modo = 'ok'; base.rechazarUid = uid5;
  await page.evaluate(() => flushPendingVentas());
  ok(base.ventas.some(v => v.uid === uid6), 'venta rechazada: la siguiente de la cola igual se guarda');
  ok((await cola()).length === 0 && (await rechazadas()).map(v => v.uid).join() === uid5, 'venta rechazada: sale de la cola y queda apartada, no se pierde');
  ok((await page.textContent('#pend-estado')).includes('1 venta(s) rechazada(s)'), 'venta rechazada: Admin la muestra');
  base.rechazarUid = null;

  // 6) Se cobra una venta mientras la cola se está enviando (internet inestable)
  base.modo = 'caida';
  const uid7 = await cobrar(1);
  base.modo = 'lenta';
  const envio = page.evaluate(() => flushPendingVentas());
  await espera(150);
  base.modo = 'caida';
  const uid8 = await cobrar(2);                       // falla y se encola mientras uid7 está en vuelo
  base.modo = 'ok';
  await envio;
  await page.evaluate(() => flushPendingVentas());
  ok(base.ventas.some(v => v.uid === uid7) && base.ventas.some(v => v.uid === uid8), 'una venta cobrada durante el envío de la cola no se pierde');
  ok((await cola()).length === 0, 'y la cola termina vacía');

  // 7) Venta anulada mientras estaba en la cola
  base.modo = 'caida';
  const uid9 = await cobrar(1);
  await page.evaluate(() => anularVenta(historial[0].id));
  base.modo = 'ok';
  await page.evaluate(() => flushPendingVentas());
  ok(base.ventas.find(v => v.uid === uid9).anulada === true, 'venta anulada en la cola: llega a la base como anulada');

  // 8) Navegador sin espacio para la copia local: la venta se cobra igual
  await page.evaluate(() => {
    const orig = Storage.prototype.setItem;
    Storage.prototype.setItem = function (k, v) { if (k === 'rpos_cache_hist' || k === 'rpos_cache_prod') throw new DOMException('lleno', 'QuotaExceededError'); return orig.call(this, k, v); };
  });
  const antes = base.ventas.length;
  const uid10 = await cobrar(1);
  ok(base.ventas.length === antes + 1 && base.ventas.some(v => v.uid === uid10), 'sin espacio para el caché: la venta igual se guarda en la base');

  // 9) Descargar copia de lo no sincronizado
  const [descarga] = await Promise.all([page.waitForEvent('download'), page.evaluate(() => exportarPendientes())]);
  const copia = JSON.parse(fs.readFileSync(await descarga.path(), 'utf8'));
  ok(copia.rechazadas.length === 1 && copia.rechazadas[0].uid === uid5 && /inválido/.test(copia.rechazadas[0].rechazo), 'la copia descargada incluye la venta rechazada y el motivo');

  // 10) La venta rechazada sigue contando tras recargar, y "Reintentar ahora" la vuelve a probar
  await page.reload();
  ok(await hasta(() => page.evaluate(u => historial.some(v => v.uid === u), uid5), 'rechazada en historial'), 'venta rechazada: sigue en el historial y el cierre después de recargar');
  base.rechazarUid = uid5;
  await page.evaluate(() => reintentarPendientes());
  ok((await rechazadas()).map(v => v.uid).join() === uid5 && (await cola()).length === 0, 'reintentar una venta que la base sigue rechazando la deja apartada (no se pierde)');
  base.rechazarUid = null;
  await page.evaluate(() => reintentarPendientes());
  ok(base.ventas.some(v => v.uid === uid5) && (await rechazadas()).length === 0 && (await cola()).length === 0, 'corregido el problema, "Reintentar ahora" guarda la venta rechazada');

  ok(new Set(base.ventas.map(v => v.uid)).size === base.ventas.length, 'ninguna venta quedó duplicada en la base');

  await browser.close(); servidor.close();
  console.log(fallas ? '\n' + fallas + ' PRUEBA(S) FALLARON' : '\nPRUEBAS DE LA APP: TODO OK');
  process.exit(fallas ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
