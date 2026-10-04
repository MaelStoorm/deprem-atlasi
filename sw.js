// Kadıköy Deprem Atlası (Kadıköy, Üsküdar, Maltepe) — internetsiz çalışma.
// Uygulama HER ZAMAN önce telefondaki kopyadan açılır (internet beklemez, zayıf çekimde takılmaz).
// İnternet varsa arka planda yeni sürüm indirilir; farklıysa sayfaya haber verilir (sayfa kendini yeniler
// ya da "Yeni sürüm hazır" şeridi gösterir).
const SURUM = "atlas-v11";
const TEMEL = ["./", "./index.html", "./gizlilik.html", "./manifest.webmanifest", "./ikon-192.png", "./ikon-512.png", "./ikon-180.png", "./yazi.ttf"];

self.addEventListener("install", e => {
  // cache: "reload" → tarayıcının kendi önbelleğini atla, sunucudaki güncel dosyayı al
  e.waitUntil(caches.open(SURUM).then(c => c.addAll(TEMEL.map(u => new Request(u, { cache: "reload" })))).then(() => self.skipWaiting()));
});
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(a => Promise.all(a.filter(k => k !== SURUM).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

const bekle = ms => new Promise(r => setTimeout(r, ms));

// Sayfanın güncel halini indir; kopyadakinden farklıysa kaydet ve açık pencerelere haber ver
async function sayfayiGuncelle(yeniPencereId) {
  const y = await fetch(new URL("./", self.registration.scope).href, { cache: "no-cache" });
  if (!y.ok) return;
  const yeni = await y.clone().text();
  const eskiYanit = await caches.match("./index.html");
  const eski = eskiYanit ? await eskiYanit.text() : null;
  if (eski === yeni) return;
  const c = await caches.open(SURUM);
  await c.put("./index.html", y.clone());
  await c.put("./", y);
  if (eski === null) return;  // ilk kurulum: haber verecek bir şey yok
  // Yeni açılan pencere birkaç yüz milisaniye içinde oluşur; onu da bekle
  for (let i = 0; i < 10 && yeniPencereId; i++) {
    if (await self.clients.get(yeniPencereId)) break;
    await bekle(300);
  }
  for (const p of await self.clients.matchAll({ type: "window" })) p.postMessage({ tip: "yeni-surum" });
}

self.addEventListener("fetch", e => {
  const r = e.request; if (r.method !== "GET") return;
  // Başka sitelere giden istekler (deprem listesi, bildirim sunucusu) her zaman doğrudan internetten
  if (!r.url.startsWith(self.location.origin)) return;
  if (r.mode === "navigate" && new URL(r.url).pathname.endsWith(".html") && !new URL(r.url).pathname.endsWith("/index.html")) {
    // Ana sayfa dışındaki sayfalar (gizlilik): internet varsa güncel hali, yoksa kopya
    e.respondWith(fetch(r).then(y => { if (y.ok) { const k = y.clone(); caches.open(SURUM).then(c => c.put(r, k)); } return y; })
      .catch(() => caches.match(r, { ignoreSearch: true }).then(v => v || caches.match("./index.html"))));
    return;
  }
  if (r.mode === "navigate") {
    // Ana sayfa: önce kopya; kopya yoksa (ilk açılış) internet
    e.waitUntil(sayfayiGuncelle(e.resultingClientId).catch(() => {}));
    e.respondWith(caches.match("./index.html").then(v => v || fetch(r).catch(() => caches.match("./"))));
    return;
  }
  // Diğer dosyalar (simgeler, yazı tipi): önce kopya, yoksa internet
  e.respondWith(caches.match(r, { ignoreSearch: true }).then(v => {
    if (v) return v;
    return fetch(r).then(y => {
      if (y && y.ok) { const k = y.clone(); caches.open(SURUM).then(c => c.put(r, k)); }
      return y;
    }).catch(() => new Response("", { status: 504 }));
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
