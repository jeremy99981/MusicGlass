import { getApiUrl } from "./backend-config";

function getCookie(name: string) {
  if (typeof document === "undefined") return "";
  return document.cookie
    .split("; ")
    .find((row) => row.startsWith(`${name}=`))
    ?.split("=")[1] ?? "";
}

function saveCSRF(body: unknown) {
  if (typeof window === "undefined" || !body || typeof body !== "object") return;
  const token = "csrf_token" in body ? body.csrf_token : null;
  if (typeof token === "string" && token) {
    window.localStorage.setItem("musicglass-csrf-token", token);
  }
  const accessToken = "access_token" in body ? body.access_token : null;
  if (typeof accessToken === "string" && accessToken) {
    window.localStorage.setItem("musicglass-access-token", accessToken);
  }
  const refreshToken = "refresh_token" in body ? body.refresh_token : null;
  if (typeof refreshToken === "string" && refreshToken) {
    window.localStorage.setItem("musicglass-refresh-token", refreshToken);
  }
}

function csrfHeaders(): Record<string, string> {
  const csrf = getCookie("mg_csrf") || (typeof window !== "undefined" ? window.localStorage.getItem("musicglass-csrf-token") ?? "" : "");
  return csrf ? { "X-CSRF-Token": decodeURIComponent(csrf) } : {};
}

async function parseError(response: Response, fallback: string) {
  try {
    const body = await response.json();
    if (typeof body.error !== "string") return fallback;
    if (body.error === "invalid credentials") return "Adresse e-mail ou mot de passe incorrect.";
    if (body.error === "email already exists") return "Ce compte existe déjà. Passez sur Connexion pour vous connecter.";
    if (body.error === "invalid csrf token") return "Session expirée. Réessayez après rechargement de la page.";
    return body.error;
  } catch {
    return fallback;
  }
}

function clearStoredSession() {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem("musicglass-csrf-token");
  window.localStorage.removeItem("musicglass-access-token");
  window.localStorage.removeItem("musicglass-refresh-token");
}

function withAuthorization(init?: RequestInit): RequestInit {
  const headers = new Headers(init?.headers);
  const token = typeof window !== "undefined" ? window.localStorage.getItem("musicglass-access-token") : "";
  if (token) headers.set("Authorization", `Bearer ${token}`);
  return { ...init, headers };
}

async function refreshSession() {
  const refreshToken = typeof window !== "undefined" ? window.localStorage.getItem("musicglass-refresh-token") ?? "" : "";
  const response = await fetch(getApiUrl("/auth/refresh"), {
    method: "POST",
    credentials: "include",
    headers: refreshToken ? { "Content-Type": "application/json" } : undefined,
    body: refreshToken ? JSON.stringify({ refresh_token: refreshToken }) : undefined,
  });
  if (!response.ok) return false;
  saveCSRF(await response.json());
  return true;
}

async function fetchWithRefresh(input: RequestInfo | URL, init?: RequestInit) {
  const first = await fetch(input, withAuthorization(init));
  if (first.status !== 401) return first;
  const refreshed = await refreshSession();
  if (!refreshed) return first;
  return fetch(input, withAuthorization(init));
}

async function fetchBuiltWithRefresh(build: () => [RequestInfo | URL, RequestInit?]) {
  const [input, init] = build();
  const first = await fetch(input, withAuthorization(init));
  if (first.status !== 401) return first;
  const refreshed = await refreshSession();
  if (!refreshed) return first;
  const [retryInput, retryInit] = build();
  return fetch(retryInput, withAuthorization(retryInit));
}

export async function signup(name: string, email: string, password: string) {
  clearStoredSession();
  const response = await fetch(getApiUrl("/auth/signup"), {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, email, password }),
  });
  if (!response.ok) throw new Error(await parseError(response, "Impossible de créer le compte."));
  saveCSRF(await response.json());
}

export async function login(email: string, password: string) {
  clearStoredSession();
  const response = await fetch(getApiUrl("/auth/login"), {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!response.ok) throw new Error(await parseError(response, "Adresse ou mot de passe incorrect."));
  saveCSRF(await response.json());
}

export async function fetchMe() {
  const response = await fetchWithRefresh(getApiUrl("/me"), { credentials: "include" });
  if (!response.ok) return null;
  return response.json() as Promise<{ id: number; name: string; email: string }>;
}

export type SearchHistoryEntry = {
  id: number;
  query: string;
  searched_at: string;
};

export async function fetchSearchHistory() {
  const response = await fetchWithRefresh(getApiUrl("/search/history"), { credentials: "include" });
  if (!response.ok) throw new Error("Impossible de charger l’historique de recherche.");
  return response.json() as Promise<SearchHistoryEntry[]>;
}

export async function recordSearchHistory(query: string) {
  const response = await fetchWithRefresh(getApiUrl("/search/history"), {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json", ...csrfHeaders() },
    body: JSON.stringify({ query }),
  });
  if (!response.ok) throw new Error("Impossible d’enregistrer la recherche.");
  return response.json() as Promise<SearchHistoryEntry>;
}

export async function clearSearchHistory() {
  const response = await fetchWithRefresh(getApiUrl("/search/history"), {
    method: "DELETE",
    credentials: "include",
    headers: csrfHeaders(),
  });
  if (!response.ok) throw new Error("Impossible d’effacer l’historique de recherche.");
}

export async function createSharedSession() {
  const response = await fetchBuiltWithRefresh(() => [getApiUrl("/sessions"), {
    method: "POST",
    credentials: "include",
    headers: csrfHeaders(),
  }]);
  if (!response.ok) throw new Error(await parseError(response, "Connectez-vous pour créer une session."));
  return response.json() as Promise<{ code: string }>;
}

export async function getSharedSession(code: string) {
  const response = await fetchWithRefresh(getApiUrl(`/sessions/${encodeURIComponent(code.trim().toUpperCase())}`), {
    credentials: "include",
  });
  if (!response.ok) throw new Error(await parseError(response, "Session introuvable ou connexion requise."));
  return response.json() as Promise<{ code: string; host_id: number }>;
}

export async function endSharedSession(code: string) {
  const response = await fetchBuiltWithRefresh(() => [getApiUrl(`/sessions/${encodeURIComponent(code.trim().toUpperCase())}`), {
    method: "DELETE",
    credentials: "include",
    headers: csrfHeaders(),
  }]);
  if (!response.ok) throw new Error(await parseError(response, "Impossible de quitter la session."));
}

export function getStoredAccessToken() {
  if (typeof window === "undefined") return "";
  return window.localStorage.getItem("musicglass-access-token") ?? "";
}
