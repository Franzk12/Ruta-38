// Service worker de RepuestoPOS: hace que la app abra aunque no haya internet.
//
// Regla principal: CON internet siempre se usa la versión publicada (nunca queda una caja
// "clavada" en una versión vieja); la copia guardada se usa solo si la red no responde.
// Los pedidos a Supabase (los datos) NO pasan por acá: de eso se ocupa la cola de index.html.
var CACHE = 'rpos-app-v1';
var ARCHIVOS = ['./', './index.html', './manifest.webmanifest', './icons/icono-192.png', './icons/icono-512.png', './vendor/xlsx.full.min.js'];
var HOSTS_FUENTES = ['fonts.googleapis.com', 'fonts.gstatic.com'];
var ESPERA_RED_MS = 4000;

self.addEventListener('install', function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) { return c.addAll(ARCHIVOS); }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener('activate', function (e) {
  e.waitUntil(caches.keys().then(function (claves) {
    return Promise.all(claves.filter(function (k) { return k.indexOf('rpos-app-') === 0 && k !== CACHE; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function guardar(req, resp) {
  if (resp && (resp.ok || resp.type === 'opaque')) {
    var copia = resp.clone();
    caches.open(CACHE).then(function (c) { c.put(req, copia); }).catch(function () { });
  }
  return resp;
}

// Red primero; si falla o tarda demasiado, la copia guardada.
function redPrimero(req) {
  var deRed = fetch(req).then(function (resp) { return guardar(req, resp); });
  var deCache = caches.match(req, { ignoreSearch: req.mode === 'navigate' }).then(function (r) {
    return r || (req.mode === 'navigate' ? caches.match('./index.html') : undefined);
  });
  return new Promise(function (resolver, rechazar) {
    var listo = false;
    function usarCache() {
      deCache.then(function (r) {
        if (listo) return;
        if (r) { listo = true; resolver(r); }
      });
    }
    var reloj = setTimeout(usarCache, ESPERA_RED_MS);
    deRed.then(function (resp) {
      clearTimeout(reloj);
      if (listo) return;
      // Un error del servidor (5xx) con copia guardada: mejor la copia
      if (!resp.ok && resp.type !== 'opaque') {
        return deCache.then(function (r) { if (!listo) { listo = true; resolver(r || resp); } });
      }
      listo = true; resolver(resp);
    }).catch(function (err) {
      clearTimeout(reloj);
      deCache.then(function (r) {
        if (listo) return;
        listo = true;
        if (r) resolver(r); else rechazar(err);
      });
    });
  });
}

// Copia guardada primero (fuentes: no cambian); se renueva por detrás.
function cachePrimero(req) {
  return caches.match(req).then(function (r) {
    var deRed = fetch(req).then(function (resp) { return guardar(req, resp); });
    if (r) { deRed.catch(function () { }); return r; }
    return deRed;
  });
}

self.addEventListener('fetch', function (e) {
  var req = e.request;
  if (req.method !== 'GET') return;
  var url = new URL(req.url);
  if (url.origin === self.location.origin) { e.respondWith(redPrimero(req)); return; }
  if (HOSTS_FUENTES.indexOf(url.hostname) >= 0) { e.respondWith(cachePrimero(req)); return; }
  // Todo lo demás (Supabase) va directo a la red, sin tocar.
});
