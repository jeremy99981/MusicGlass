import { getApiUrl, resolveBackendResource } from "./backend-config";
import { csrfHeaders, fetchWithRefresh } from "./auth-http";

export { getApiBase, getWebSocketBaseUrl } from "./backend-config";

export async function fetchHome() {
  const res = await fetch(getApiUrl("/catalog/home"));
  if (!res.ok) throw new Error("Failed to fetch home catalog");
  return res.json();
}

export async function fetchSearch(query: string) {
  const res = await fetch(`${getApiUrl("/catalog/search")}?q=${encodeURIComponent(query)}`);
  if (!res.ok) throw new Error("Failed to fetch search results");
  return res.json();
}

export async function fetchPlaylist(id: string) {
  const res = await fetch(getApiUrl(`/catalog/playlist/${encodeURIComponent(id)}`));
  if (!res.ok) throw new Error("Failed to fetch playlist");
  return res.json();
}

export function getAudioStreamUrl(trackId: string) {
  return getApiUrl(`/media/stream/${trackId}`);
}

export function getMediaArtworkUrl(artworkUrl: string) {
  return `${getApiUrl("/media/artwork")}?url=${encodeURIComponent(artworkUrl)}`;
}

export type ResolvedAudioStream = {
  stream_url: string;
  resolved_track_id?: string;
  cached: boolean;
  expires_in_seconds?: number;
  duration_seconds?: number;
};

const audioResolveCache = new Map<string, { expiresAt: number; promise: Promise<ResolvedAudioStream> }>();

function audioResolveKey(track: string | { id: string; title?: string; artist?: string }) {
  if (typeof track === "string") return track;
  return `${track.id}|${track.title ?? ""}|${track.artist ?? ""}`;
}

export async function resolveAudioStream(track: string | { id: string; title?: string; artist?: string }) {
  const cacheKey = audioResolveKey(track);
  const cached = audioResolveCache.get(cacheKey);
  if (cached && cached.expiresAt > Date.now() + 30_000) {
    return cached.promise;
  }

  const trackId = typeof track === "string" ? track : track.id;
  const params = new URLSearchParams();
  if (typeof track !== "string") {
    if (track.title) params.set("title", track.title);
    if (track.artist) params.set("artist", track.artist);
  }
  const query = params.toString();
  const promise = (async () => {
    const controller = new AbortController();
    const timeout = globalThis.setTimeout(() => controller.abort(), 6500);
    const res = await fetch(`${getApiUrl(`/media/resolve/${encodeURIComponent(trackId)}`)}${query ? `?${query}` : ""}`, {
      signal: controller.signal,
    }).finally(() => globalThis.clearTimeout(timeout));
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      throw new Error(typeof body?.error === "string" ? body.error : "Failed to resolve audio stream");
    }
    const body = await res.json() as ResolvedAudioStream;
    body.stream_url = resolveBackendResource(body.stream_url);
    const ttl = Math.max(30, Math.min(body.expires_in_seconds ?? 600, 2400));
    audioResolveCache.set(cacheKey, { promise: Promise.resolve(body), expiresAt: Date.now() + ttl * 1000 });
    return body;
  })();

  audioResolveCache.set(cacheKey, { promise, expiresAt: Date.now() + 90_000 });
  promise.catch(() => audioResolveCache.delete(cacheKey));
  return promise;
}

export function invalidateAudioStream(track: string | { id: string; title?: string; artist?: string }) {
  audioResolveCache.delete(audioResolveKey(track));
}

export async function fetchRadio(track: { id: string; title: string; artist: string }, signal?: AbortSignal) {
  const params = new URLSearchParams({
    track_id: track.id,
    title: track.title,
    artist: track.artist,
  });
  const res = await fetch(`${getApiUrl("/catalog/radio")}?${params.toString()}`, { signal });
  if (!res.ok) throw new Error("Failed to fetch radio queue");
  return res.json() as Promise<{ seed: unknown; tracks: unknown[]; source: string }>;
}

export type LibrarySong = {
  id: number;
  external_id: string;
  title: string;
  artist: string;
  album?: string;
  cover_url?: string;
  duration_ms?: number;
};

export type LibraryLike = {
  id: number;
  song: LibrarySong;
  is_public?: boolean;
  created_at?: string;
};

export type LibraryPlaylist = {
  id: number;
  name: string;
  description?: string;
  is_public?: boolean;
  song_count?: number;
};

export type ProviderStatus = {
  id: string;
  name: string;
  connected: boolean;
  oauth_connected?: boolean;
  oauth_available?: boolean;
  playback_ready?: boolean;
  status: string;
  server_only: boolean;
  auth_url?: string;
  message?: string;
};

export async function fetchLibrary() {
  const res = await fetchWithRefresh(getApiUrl("/library"), { credentials: "include" });
  if (!res.ok) throw new Error("Failed to fetch library");
  return res.json() as Promise<{ likes: LibraryLike[]; playlists: LibraryPlaylist[]; provider: ProviderStatus }>;
}

export async function createLibraryPlaylist(name: string) {
  const res = await fetchWithRefresh(getApiUrl("/library/playlists"), {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json", ...csrfHeaders() },
    body: JSON.stringify({ name }),
  });
  if (!res.ok) throw new Error("Failed to create playlist");
  return res.json() as Promise<LibraryPlaylist>;
}

export async function connectYouTubeProvider() {
  const res = await fetchWithRefresh(getApiUrl("/providers/youtube/connect"), {
    method: "POST",
    credentials: "include",
    headers: csrfHeaders(),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(typeof body?.error === "string" ? body.error : "YouTube Music connection failed");
  return body as ProviderStatus;
}

export async function fetchYouTubeProviderStatus() {
  const res = await fetchWithRefresh(getApiUrl("/providers/youtube"), { credentials: "include" });
  if (!res.ok) throw new Error("Failed to fetch YouTube Music status");
  return res.json() as Promise<ProviderStatus>;
}

export async function addLibraryLike(track: { id: string; title: string; artist: string; album?: string; artwork?: string; duration?: number }) {
  const durationMs = track.duration ? Math.round(track.duration * 1000) : undefined;
  const res = await fetchWithRefresh(getApiUrl("/library/likes"), {
    method: "POST",
    credentials: "include",
    headers: { "Content-Type": "application/json", ...csrfHeaders() },
    body: JSON.stringify({
      external_id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album || undefined,
      cover_url: track.artwork || undefined,
      duration_ms: durationMs,
    }),
  });
  if (!res.ok && res.status !== 409) throw new Error("Failed to like track");
  return res.status === 409 ? null : (res.json() as Promise<LibraryLike>);
}
