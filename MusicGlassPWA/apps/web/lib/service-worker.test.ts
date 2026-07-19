import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it, vi } from "vitest";

type WorkerListener = (event: never) => void;

function loadServiceWorker(cacheOverrides: Record<string, unknown> = {}) {
  const listeners = new Map<string, WorkerListener>();
  const worker = {
    location: { origin: "https://musicglass.test" },
    registration: { navigationPreload: { enable: vi.fn().mockResolvedValue(undefined) } },
    clients: { claim: vi.fn().mockResolvedValue(undefined) },
    skipWaiting: vi.fn().mockResolvedValue(undefined),
    addEventListener: vi.fn((type: string, listener: WorkerListener) => listeners.set(type, listener)),
  };
  const cacheStorage = {
    keys: vi.fn().mockResolvedValue([]),
    delete: vi.fn().mockResolvedValue(true),
    match: vi.fn(),
    open: vi.fn(),
    ...cacheOverrides,
  };
  const networkFetch = vi.fn();
  const source = readFileSync(resolve(process.cwd(), "public/sw.js"), "utf8");
  new Function("self", "caches", "fetch", "Response", source)(
    worker,
    cacheStorage,
    networkFetch,
    { error: vi.fn(() => ({ status: 0 })) },
  );
  return { listeners, worker, cacheStorage, networkFetch };
}

describe("service worker", () => {
  it("only removes obsolete MusicGlass caches during activation", async () => {
    const { listeners, worker, cacheStorage } = loadServiceWorker({
      keys: vi.fn().mockResolvedValue([
        "musicglass-precache-v7-player-workspace",
        "musicglass-precache-v9",
        "musicglass-runtime-v9",
        "musicglass-precache-v10",
        "musicglass-runtime-v10",
        "musicglass-precache-v11",
        "musicglass-runtime-v11",
        "musicglass-precache-v12",
        "musicglass-runtime-v12",
        "musicglass-precache-v13",
        "musicglass-runtime-v13",
        "unrelated-feature-cache",
      ]),
    });
    let activation: Promise<unknown> = Promise.resolve();

    listeners.get("activate")?.({ waitUntil: (promise: Promise<unknown>) => { activation = promise; } } as never);
    await activation;

    expect(cacheStorage.delete).toHaveBeenCalledTimes(11);
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-precache-v7-player-workspace");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-precache-v9");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-runtime-v9");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-precache-v10");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-runtime-v10");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-precache-v11");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-runtime-v11");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-precache-v12");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-runtime-v12");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-precache-v13");
    expect(cacheStorage.delete).toHaveBeenCalledWith("musicglass-runtime-v13");
    expect(worker.registration.navigationPreload.enable).toHaveBeenCalledOnce();
    expect(worker.clients.claim).toHaveBeenCalledOnce();
  });

  it("does not intercept API or byte-range requests", () => {
    const { listeners } = loadServiceWorker();
    const respondWith = vi.fn();
    const baseRequest = {
      method: "GET",
      mode: "cors",
      destination: "audio",
      headers: { has: vi.fn(() => false) },
    };

    listeners.get("fetch")?.({
      request: { ...baseRequest, url: "https://musicglass.test/api/audio/track" },
      respondWith,
    } as never);
    listeners.get("fetch")?.({
      request: { ...baseRequest, url: "https://musicglass.test/audio/track", headers: { has: vi.fn(() => true) } },
      respondWith,
    } as never);

    expect(respondWith).not.toHaveBeenCalled();
  });

  it("retries navigation on the network when preload fails", async () => {
    const { listeners, networkFetch } = loadServiceWorker();
    const networkResponse = { ok: true, source: "network" };
    networkFetch.mockResolvedValue(networkResponse);
    let response: Promise<unknown> = Promise.resolve();

    listeners.get("fetch")?.({
      request: {
        method: "GET",
        mode: "navigate",
        destination: "document",
        url: "https://musicglass.test/library",
        headers: { has: vi.fn(() => false) },
      },
      preloadResponse: Promise.reject(new Error("preload unavailable")),
      respondWith: (promise: Promise<unknown>) => { response = promise; },
      waitUntil: vi.fn(),
    } as never);

    await expect(response).resolves.toBe(networkResponse);
    expect(networkFetch).toHaveBeenCalledOnce();
  });

  it("serves a previously visited navigation before the generic offline page", async () => {
    const cachedNavigation = { ok: true, source: "runtime-cache" };
    const match = vi.fn().mockResolvedValue(cachedNavigation);
    const { listeners, networkFetch } = loadServiceWorker({ match });
    networkFetch.mockRejectedValue(new Error("offline"));
    const request = {
      method: "GET",
      mode: "navigate",
      destination: "document",
      url: "https://musicglass.test/library",
      headers: { has: vi.fn(() => false) },
    };
    let response: Promise<unknown> = Promise.resolve();

    listeners.get("fetch")?.({
      request,
      preloadResponse: Promise.resolve(undefined),
      respondWith: (promise: Promise<unknown>) => { response = promise; },
      waitUntil: vi.fn(),
    } as never);

    await expect(response).resolves.toBe(cachedNavigation);
    expect(match).toHaveBeenCalledWith(request);
    expect(match).not.toHaveBeenCalledWith("/offline");
  });
});
