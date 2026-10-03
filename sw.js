// Kadıköy Deprem Atlası — internetsiz çalışma.
// Uygulama HER ZAMAN önce telefondaki kopyadan açılır (internet beklemez, zayıf çekimde takılmaz).
// İnternet varsa arka planda yeni sürüm indirilir; bir sonraki açılışta o gösterilir.
const SURUM = "atlas-v7";
const TEMEL = ["./", "./index.html", "./gizlilik.html", "./manifest.webmanifest", "./ikon-192.png", "./ikon-512.png", "./ikon-180.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(SURUM).then(c => c.addAll(TEMEL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(a => Promise.all(a.filter(k => k !== SURUM).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

// Arka planda güncelle: başarılı olursa kopyayı yeniler, hata olursa sessizce geçer
function guncelle(istek, anahtar) {
  return fetch(istek).then(y => {
    if (y && (y.ok || y.type === "opaque")) { const k = y.clone(); caches.open(SURUM).then(c => c.put(anahtar || istek, k)); }
    return y;
  });
}

self.addEventListener("fetch", e => {
  const r = e.request; if (r.method !== "GET") return;
  // Deprem listesi ve bildirim sunucusu her zaman internetten gelsin (telefonda eski liste saklanmasın)
  if (r.url.includes(".workers.dev")) return;
  if (r.mode === "navigate") {
    // Sayfa: önce kopya; kopya yoksa (ilk açılış) internet
    const ag = guncelle(r, "./index.html").catch(() => null);
    e.waitUntil(ag);
    e.respondWith(caches.match("./index.html").then(v => v || ag.then(y => y || caches.match("./"))));
    return;
  }
  // Diğer dosyalar (simgeler, yazı tipi): önce kopya, yoksa internet
  e.respondWith(caches.match(r, { ignoreSearch: r.url.startsWith(self.location.origin) }).then(v => {
    if (v) return v;
    return guncelle(r).catch(() => new Response("", { status: 504 }));
  }));
});

// Deprem bildirimi geldiğinde göster
self.addEventListener("push", e => {
  let v = {}; try { v = e.data ? e.data.json() : {}; } catch { v = { baslik: "Deprem bildirimi", govde: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(v.baslik || "Deprem bildirimi", {
    body: v.govde || "", icon: "ikon-192.png", badge: "ikon-192.png", tag: v.id || "deprem", renotify: true,
    data: { url: "./?deprem=" + encodeURIComponent(v.id || "") }
  }));
});
// Bildirime dokununca uygulamayı "Son depremler" bölümünde aç
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const hedef = new URL(e.notification.data?.url || "./", self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then(l => {
    for (const c of l) if (c.url.startsWith(self.registration.scope) && "focus" in c) { c.navigate(hedef); return c.focus(); }
    return self.clients.openWindow(hedef);
  }));
});
