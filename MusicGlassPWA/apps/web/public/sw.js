const CACHE_PREFIX = "musicglass-";
const CACHE_VERSION = "v20";
const PRECACHE = `${CACHE_PREFIX}precache-${CACHE_VERSION}`;
const RUNTIME = `${CACHE_PREFIX}runtime-${CACHE_VERSION}`;
const CURRENT_CACHES = new Set([PRECACHE, RUNTIME]);
const PRECACHE_URLS = [
  "/offline",
  "/manifest.webmanifest",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
  "/icons/icon-maskable-512.png",
];
const RUNTIME_LIMIT = 80;

async function cacheResponse(cacheName, request, response) {
  if (!response || !response.ok || response.type === "opaque") return;
  const cache = await caches.open(cacheName);
  await cache.put(request, response.clone());
  if (cacheName === RUNTIME) {
    const keys = await cache.keys();
    await Promise.all(keys.slice(0, Math.max(0, keys.length - RUNTIME_LIMIT)).map((key) => cache.delete(key)));
  }
}

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(PRECACHE);
    await Promise.all(PRECACHE_URLS.map((url) => cache.add(url).catch(() => undefined)));
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key.startsWith(CACHE_PREFIX) && !CURRENT_CACHES.has(key))
        .map((key) => caches.delete(key)),
    );
    if (self.registration.navigationPreload) {
      await self.registration.navigationPreload.enable();
    }
    await self.clients.claim();
  })());
});

async function navigateNetworkFirst(event) {
  try {
    const preloaded = await Promise.resolve(event.preloadResponse).catch(() => undefined);
    const response = preloaded || await fetch(event.request);
    event.waitUntil(cacheResponse(RUNTIME, event.request, response).catch(() => undefined));
    return response;
  } catch {
    return (await caches.match(event.request)) || (await caches.match("/offline")) || Response.error();
  }
}

async function staticCacheFirst(event) {
  const cached = await caches.match(event.request);
  if (cached) return cached;
  const response = await fetch(event.request);
  event.waitUntil(cacheResponse(RUNTIME, event.request, response).catch(() => undefined));
  return response;
}

async function imageStaleWhileRevalidate(event) {
  const cached = await caches.match(event.request);
  const network = fetch(event.request).then(async (response) => {
    await cacheResponse(RUNTIME, event.request, response).catch(() => undefined);
    return response;
  });
  if (cached) {
    event.waitUntil(network.then(() => undefined).catch(() => undefined));
    return cached;
  }
  return cached || network;
}

self.addEventListener("fetch", (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (
    request.method !== "GET"
    || request.headers.has("range")
    || url.origin !== self.location.origin
    || url.pathname.startsWith("/api/")
  ) {
    return;
  }

  if (request.mode === "navigate") {
    event.respondWith(navigateNetworkFirst(event));
    return;
  }

  if (request.destination === "image") {
    event.respondWith(imageStaleWhileRevalidate(event));
    return;
  }

  if (url.pathname.startsWith("/_next/static/") || ["style", "script", "font"].includes(request.destination)) {
    event.respondWith(staticCacheFirst(event));
  }
});
