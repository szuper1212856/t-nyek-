const CACHE = "tenyek-v1";
const SHELL = ["./", "./config.js", "./manifest.webmanifest", "./icons/icon-192.png", "./icons/badge-96.png"];

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(CACHE)
      .then(cache => Promise.all(SHELL.map(url => cache.add(url).catch(() => {}))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", event => {
  const req = event.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  event.respondWith(
    fetch(req)
      .then(res => {
        if (res.ok && res.type === "basic") {
          const copy = res.clone();
          caches.open(CACHE).then(cache => cache.put(req, copy));
        }
        return res;
      })
      .catch(async () => {
        const hit = await caches.match(req, { ignoreSearch: true });
        if (hit) return hit;
        if (req.mode === "navigate") {
          const home = await caches.match(new URL("./", self.registration.scope).href);
          if (home) return home;
        }
        return Response.error();
      })
  );
});

self.addEventListener("push", event => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    data = { body: event.data ? event.data.text() : "" };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || "Tények++", {
      body: data.body || "Új adás jelent meg.",
      icon: "icons/icon-192.png",
      badge: "icons/badge-96.png",
      tag: data.tag || "tenyek",
      data: { url: data.url || "./" }
    })
  );
});

self.addEventListener("notificationclick", event => {
  event.notification.close();
  const target = new URL((event.notification.data && event.notification.data.url) || "./", self.registration.scope).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const win of windows) {
      if (win.url.startsWith(self.registration.scope) && !win.url.includes("/szerkesztoseg/")) {
        await win.focus();
        if ("navigate" in win) {
          try { await win.navigate(target); } catch (e) {}
        }
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
