/* Vortex SiteTrack service worker — offline shell */
const CACHE = "sitetrack-v12";
const ASSETS = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS).catch(()=>{})).then(() => self.skipWaiting()));
});

self.addEventListener("activate", e => {
  e.waitUntil(
    caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", e => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);

  // never cache Supabase API / storage traffic
  if (/supabase\.(co|in)/.test(url.host)) return;

  // the page itself: network first so updates appear, cache as fallback
  if (req.mode === "navigate" || url.pathname.endsWith("/") || url.pathname.endsWith("index.html")) {
    e.respondWith(
      fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put("./index.html", copy));
        return res;
      }).catch(() => caches.match("./index.html"))
    );
    return;
  }

  // fonts + CDN libraries + icons: cache first
  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res.ok && (url.origin === location.origin || /fonts\.(googleapis|gstatic)\.com|cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com/.test(url.host))) {
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy));
      }
      return res;
    }).catch(() => hit))
  );
});
