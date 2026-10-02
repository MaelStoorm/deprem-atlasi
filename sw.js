// Kadıköy Deprem Atlası — internetsiz çalışma.
// Sayfa: önce internetten dener (güncel sürüm gelsin), olmazsa telefondaki kopyayı açar.
// Diğer dosyalar (simge, yazı tipi): önce telefondaki kopya.
const SURUM = "atlas-v4";
const TEMEL = ["./", "./index.html", "./manifest.webmanifest", "./ikon-192.png", "./ikon-512.png", "./ikon-180.png"];
self.addEventListener("install", e => { e.waitUntil(caches.open(SURUM).then(c => c.addAll(TEMEL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(a => Promise.all(a.filter(k => k !== SURUM).map(k => caches.delete(k)))).then(() => self.clients.claim())); });
self.addEventListener("fetch", e => {
  const r = e.request; if (r.method !== "GET") return;
  if (r.mode === "navigate") {
    e.respondWith(fetch(r).then(y => { const k = y.clone(); caches.open(SURUM).then(c => c.put("./index.html", k)); return y; })
      .catch(() => caches.match("./index.html")));
    return;
  }
  e.respondWith(caches.match(r).then(v => v || fetch(r).then(y => {
    if (y.ok || y.type === "opaque") { const k = y.clone(); caches.open(SURUM).then(c => c.put(r, k)); }
    return y; })));
});
