import { getApiUrl } from "./backend-config";
import {
  clearStoredSession,
  csrfHeaders,
  fetchBuiltWithRefresh,
  fetchWithRefresh,
  getStoredAccessToken,
  saveSession,
} from "./auth-http";

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

export async function signup(name: string, email: string, password: string) {
  clearStoredSession();
  const response = await fetch(getApiUrl("/auth/signup"), {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name, email, password }),
  });
  if (!response.ok) throw new Error(await parseError(response, "Impossible de créer le compte."));
  saveSession(await response.json());
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
  saveSession(await response.json());
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

export { getStoredAccessToken };
