import { getApiUrl } from "./backend-config";

// Primitives partagées pour les appels API v2 authentifiés (cookies HttpOnly
// same-origin + jeton CSRF + repli localStorage). Utilisées par lib/api.ts et
// lib/session-api.ts pour éviter toute divergence de logique de session.

const CSRF_KEY = "musicglass-csrf-token";
const ACCESS_KEY = "musicglass-access-token";
const REFRESH_KEY = "musicglass-refresh-token";

export function getCookie(name: string) {
  if (typeof document === "undefined") return "";
  return document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${name}=`))
    ?.split("=")[1] ?? "";
}

export function csrfHeaders(): Record<string, string> {
  const csrf = getCookie("mg_csrf")
    || (typeof window !== "undefined" ? window.localStorage.getItem(CSRF_KEY) ?? "" : "");
  return csrf ? { "X-CSRF-Token": decodeURIComponent(csrf) } : {};
}

/** Persiste les jetons renvoyés par un signup/login/refresh (repli non-cookie). */
export function saveSession(body: unknown) {
  if (typeof window === "undefined" || !body || typeof body !== "object") return;
  const record = body as Record<string, unknown>;
  const put = (key: string, value: unknown) => {
    if (typeof value === "string" && value) window.localStorage.setItem(key, value);
  };
  put(CSRF_KEY, record.csrf_token);
  put(ACCESS_KEY, record.access_token);
  put(REFRESH_KEY, record.refresh_token);
}

export function clearStoredSession() {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(CSRF_KEY);
  window.localStorage.removeItem(ACCESS_KEY);
  window.localStorage.removeItem(REFRESH_KEY);
}

export function getStoredAccessToken() {
  if (typeof window === "undefined") return "";
  return window.localStorage.getItem(ACCESS_KEY) ?? "";
}

function withAuthorization(init?: RequestInit): RequestInit {
  const headers = new Headers(init?.headers);
  const token = getStoredAccessToken();
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return { ...init, headers };
}

async function refreshSession() {
  const refreshToken = typeof window !== "undefined" ? window.localStorage.getItem(REFRESH_KEY) ?? "" : "";
  const response = await fetch(getApiUrl("/auth/refresh"), {
    method: "POST",
    credentials: "include",
    headers: refreshToken ? { "Content-Type": "application/json" } : undefined,
    body: refreshToken ? JSON.stringify({ refresh_token: refreshToken }) : undefined,
  });
  if (!response.ok) return false;
  try {
    saveSession(await response.json());
  } catch {
    // Un cookie rafraîchi suffit pour les appels same-origin suivants.
  }
  return true;
}

/** Exécute la requête, et en cas de 401 tente un refresh puis rejoue une fois. */
export async function fetchWithRefresh(input: RequestInfo | URL, init?: RequestInit) {
  const first = await fetch(input, withAuthorization(init));
  if (first.status !== 401) return first;
  const refreshed = await refreshSession();
  if (!refreshed) return first;
  return fetch(input, withAuthorization(init));
}

/** Variante où l'URL/init est reconstruite à chaque tentative (headers CSRF frais). */
export async function fetchBuiltWithRefresh(build: () => [RequestInfo | URL, RequestInit?]) {
  const [input, init] = build();
  const first = await fetch(input, withAuthorization(init));
  if (first.status !== 401) return first;
  const refreshed = await refreshSession();
  if (!refreshed) return first;
  const [retryInput, retryInit] = build();
  return fetch(retryInput, withAuthorization(retryInit));
}
