export const BACKEND_STORAGE_KEY = "musicglass-backend-origin";
export const BACKEND_CHANGED_EVENT = "musicglass:backend-changed";

function isRetiredBackendOrigin(value: string) {
  try {
    const hostname = new URL(value).hostname.toLowerCase();
    return hostname === "usbx.me" || hostname.endsWith(".usbx.me");
  } catch {
    return true;
  }
}

function stripApiPath(value: string) {
  return value.replace(/\/(?:api(?:\/v2)?)\/?$/i, "").replace(/\/$/, "");
}

export function normalizeBackendOrigin(value: string) {
  const candidate = value.trim();
  if (!candidate) return "";

  const withProtocol = /^https?:\/\//i.test(candidate) ? candidate : `https://${candidate}`;
  const url = new URL(withProtocol);
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("Le backend doit utiliser HTTP ou HTTPS.");
  }
  url.hash = "";
  url.search = "";
  url.pathname = stripApiPath(url.pathname);
  return url.toString().replace(/\/$/, "");
}

export function getBackendOrigin() {
  if (typeof window !== "undefined") {
    const stored = window.localStorage.getItem(BACKEND_STORAGE_KEY);
    if (stored) {
      const normalized = normalizeBackendOrigin(stored);
      if (!isRetiredBackendOrigin(normalized)) return normalized;
      window.localStorage.removeItem(BACKEND_STORAGE_KEY);
    }
  }
  const configured = process.env.NEXT_PUBLIC_BACKEND_ORIGIN || process.env.NEXT_PUBLIC_API_BASE_URL || "";
  if (!configured || configured.startsWith("/")) return "";
  return normalizeBackendOrigin(configured);
}

export function getApiBase() {
  const origin = getBackendOrigin();
  return origin ? `${origin}/api/v2` : "/api/v2";
}

export function getApiUrl(path: string) {
  return `${getApiBase()}${path.startsWith("/") ? path : `/${path}`}`;
}

export function getWebSocketBaseUrl() {
  return getBackendOrigin() || (typeof window !== "undefined" ? window.location.origin : "");
}

export function setBackendOrigin(value: string) {
  if (typeof window === "undefined") return;
  const origin = normalizeBackendOrigin(value);
  if (origin) window.localStorage.setItem(BACKEND_STORAGE_KEY, origin);
  else window.localStorage.removeItem(BACKEND_STORAGE_KEY);
  window.dispatchEvent(new CustomEvent(BACKEND_CHANGED_EVENT, { detail: origin }));
}

export function resolveBackendResource(value: string) {
  if (/^https?:\/\//i.test(value)) return value;
  const origin = getBackendOrigin();
  if (!origin) return value;
  return new URL(value, origin).toString();
}

export async function probeBackend(value: string, signal?: AbortSignal) {
  const origin = normalizeBackendOrigin(value);
  const base = origin ? `${origin}/api/v2` : "/api/v2";
  const response = await fetch(`${base}/health`, { signal, cache: "no-store" });
  if (!response.ok) throw new Error(`Le backend répond avec le statut ${response.status}.`);
  const body = await response.json().catch(() => null) as { status?: string } | null;
  if (body?.status !== "ok") throw new Error("La réponse du backend est invalide.");
  return { origin, status: "ok" as const };
}
