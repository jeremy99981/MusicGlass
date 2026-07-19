import { afterEach, describe, expect, it, vi } from "vitest";
import {
  BACKEND_STORAGE_KEY,
  getApiBase,
  getBackendOrigin,
  getWebSocketBaseUrl,
  normalizeBackendOrigin,
  probeBackend,
  resolveBackendResource,
  setBackendOrigin,
} from "./backend-config";

describe("runtime backend configuration", () => {
  afterEach(() => {
    localStorage.clear();
    vi.unstubAllGlobals();
  });

  it("normalizes hostnames and strips API paths", () => {
    expect(normalizeBackendOrigin("music.example.com/api/v2/ ")).toBe("https://music.example.com");
    expect(normalizeBackendOrigin("http://192.168.1.12:8090/api")).toBe("http://192.168.1.12:8090");
  });

  it("uses one origin for REST, media and WebSocket", () => {
    setBackendOrigin("https://music.example.com/api/v2");
    expect(getApiBase()).toBe("https://music.example.com/api/v2");
    expect(getWebSocketBaseUrl()).toBe("https://music.example.com");
    expect(resolveBackendResource("/api/v2/media/stream/song-1")).toBe("https://music.example.com/api/v2/media/stream/song-1");
  });

  it("removes retired USBX backends instead of restoring a dead media origin", () => {
    localStorage.setItem(BACKEND_STORAGE_KEY, "https://seerr-litchichevelu.leto.usbx.me");

    expect(getBackendOrigin()).toBe("");
    expect(getApiBase()).toBe("/api/v2");
    expect(localStorage.getItem(BACKEND_STORAGE_KEY)).toBeNull();
  });

  it("validates the backend health response", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ status: "ok" }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);
    await expect(probeBackend("https://music.example.com")).resolves.toEqual({ origin: "https://music.example.com", status: "ok" });
    expect(fetchMock).toHaveBeenCalledWith("https://music.example.com/api/v2/health", expect.objectContaining({ cache: "no-store" }));
  });
});
