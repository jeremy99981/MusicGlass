import { afterEach, describe, expect, it, vi } from "vitest";
import { createSharedSession, getSharedSession, getStoredAccessToken, login, signup } from "./session-api";

describe("session api client", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
    Object.defineProperty(document, "cookie", { value: "", writable: true });
  });

  it("logs in and signs up with same-origin credentials", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ authenticated: true, access_token: "access-123" }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await login("user@example.com", "password123");
    await signup("Lucas", "lucas@example.com", "password123");

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v2/auth/login", expect.objectContaining({ credentials: "include" }));
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v2/auth/signup", expect.objectContaining({ credentials: "include" }));
    expect(getStoredAccessToken()).toBe("access-123");
  });

  it("creates and joins shared sessions", async () => {
    Object.defineProperty(document, "cookie", { value: "mg_csrf=token-123", writable: true });
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: "ABC12345" }), { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: "ABC12345", host_id: 1 }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(createSharedSession()).resolves.toEqual({ code: "ABC12345" });
    await expect(getSharedSession("abc12345")).resolves.toEqual({ code: "ABC12345", host_id: 1 });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v2/sessions", expect.objectContaining({ method: "POST" }));
    const createHeaders = new Headers(fetchMock.mock.calls[0]?.[1]?.headers);
    expect(createHeaders.get("X-CSRF-Token")).toBe("token-123");
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v2/sessions/ABC12345", expect.objectContaining({
      credentials: "include",
    }));
  });

  it("refreshes and retries protected session requests", async () => {
    Object.defineProperty(document, "cookie", { value: "mg_csrf=old-token", writable: true });
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ authenticated: true, csrf_token: "new-token", access_token: "new-access" }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: "ZXCVBN12" }), { status: 201 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(createSharedSession()).resolves.toEqual({ code: "ZXCVBN12" });

    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v2/auth/refresh", expect.objectContaining({
      method: "POST",
      credentials: "include",
    }));
    expect(getStoredAccessToken()).toBe("new-access");
  });
});
