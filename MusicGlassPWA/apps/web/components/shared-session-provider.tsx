"use client";

import { useEffect, useMemo, useRef } from "react";
import { getWebSocketBaseUrl } from "@/lib/api";
import { getStoredAccessToken } from "@/lib/session-api";
import { DEFAULT_ACCENT, type Track } from "@/lib/catalog";
import { usePlaybackStore } from "@/store/playback-store";
import { useSharedSessionStore, type SharedParticipant } from "@/store/shared-session-store";

type SongInfo = {
  external_id: string;
  title: string;
  artist: string;
  cover_url?: string;
  cover_urls?: string[];
  duration_ms?: number;
};

type PlaybackPayload = {
  song?: SongInfo | null;
  queue?: SongInfo[];
  is_playing?: boolean;
  position_ms?: number;
  updated_at?: string;
  participants?: SharedParticipant[];
};

type WSMessage = {
  type: "state" | "sync" | "play" | "pause" | "seek" | "next" | "joined" | "left" | "host_left" | "error";
  payload?: PlaybackPayload | SharedParticipant | { message?: string };
};

function songToTrack(song: SongInfo): Track {
  return {
    id: song.external_id,
    title: song.title,
    artist: song.artist,
    album: "",
    artwork: song.cover_urls?.[0] || song.cover_url || "",
    duration: song.duration_ms ? song.duration_ms / 1000 : 0,
    accent: DEFAULT_ACCENT,
  };
}

function trackToSong(track: Track, duration = track.duration): SongInfo {
  return {
    external_id: track.id,
    title: track.title,
    artist: track.artist,
    cover_url: track.artwork,
    cover_urls: track.artwork ? [track.artwork] : [],
    duration_ms: Math.round((duration || 0) * 1000),
  };
}

function correctedPositionSeconds(payload: PlaybackPayload) {
  const base = (payload.position_ms ?? 0) / 1000;
  if (!payload.is_playing || !payload.updated_at) return base;
  const delta = (Date.now() - new Date(payload.updated_at).getTime()) / 1000;
  const position = Math.max(0, base + delta);
  const duration = (payload.song?.duration_ms ?? 0) / 1000;
  return duration > 0 ? Math.min(position, duration) : position;
}

function websocketURL(code: string, role: string, clientId: string) {
  const base = getWebSocketBaseUrl() || window.location.origin;
  const url = new URL(base);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = `/api/v2/sessions/${encodeURIComponent(code)}/ws`;
  url.searchParams.set("role", role);
  url.searchParams.set("client_id", clientId);
  const token = getStoredAccessToken();
  if (token) url.searchParams.set("token", token);
  return url.toString();
}

function applyRemoteState(payload: PlaybackPayload) {
  const song = payload.song;
  if (!song) {
    usePlaybackStore.getState().setPlaying(false);
    return;
  }
  const current = songToTrack(song);
  const queue = payload.queue?.length ? payload.queue.map(songToTrack) : [current];
  usePlaybackStore.getState().applyRemotePlayback({
    current,
    queue,
    isPlaying: Boolean(payload.is_playing),
    position: correctedPositionSeconds(payload),
  });
}

export function SharedSessionProvider() {
  const code = useSharedSessionStore((state) => state.code);
  const isHost = useSharedSessionStore((state) => state.isHost);
  const socketRef = useRef<WebSocket | null>(null);
  const clientId = useMemo(
    () => `web-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`,
    [],
  );

  useEffect(() => {
    if (!code) {
      socketRef.current?.close();
      socketRef.current = null;
      return;
    }

    const role = isHost ? "host" : "guest";
    const socket = new WebSocket(websocketURL(code, role, clientId));
    socketRef.current = socket;
    useSharedSessionStore.getState().setStatus("connecting");

    socket.addEventListener("open", () => {
      useSharedSessionStore.getState().setStatus("connected");
      if (isHost) sendHostSync(socket);
    });

    socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data as string) as WSMessage;
      if (message.type === "error") {
        const payload = message.payload as { message?: string } | undefined;
        useSharedSessionStore.getState().setError(payload?.message ?? "Erreur de session.");
        return;
      }
      useSharedSessionStore.getState().setStatus("connected");
      useSharedSessionStore.getState().setError(null);
      if (message.type === "host_left") {
        useSharedSessionStore.getState().setError("L’hôte a quitté la session.");
        usePlaybackStore.getState().setPlaying(false);
        return;
      }
      if (message.type === "joined") {
        useSharedSessionStore.getState().addParticipant(message.payload as SharedParticipant);
        return;
      }
      if (message.type === "left") {
        useSharedSessionStore.getState().removeParticipant(message.payload as SharedParticipant);
        return;
      }
      const payload = message.payload as PlaybackPayload | undefined;
      if (payload?.participants) {
        useSharedSessionStore.getState().setParticipants(payload.participants);
      }
      if (!isHost && payload && ["state", "sync", "play", "pause", "seek", "next"].includes(message.type)) {
        applyRemoteState(payload);
      }
    });

    socket.addEventListener("close", () => {
      if (socketRef.current === socket) {
        useSharedSessionStore.getState().setStatus("disconnected");
      }
    });

    socket.addEventListener("error", () => {
      if (socket.readyState !== WebSocket.OPEN) {
        useSharedSessionStore.getState().setError("Connexion WebSocket impossible.");
      }
    });

    return () => {
      socket.close();
      if (socketRef.current === socket) socketRef.current = null;
    };
  }, [clientId, code, isHost]);

  useEffect(() => {
    if (!isHost) return;
    let timeout: ReturnType<typeof setTimeout> | null = null;
    return usePlaybackStore.subscribe(() => {
      if (timeout) clearTimeout(timeout);
      timeout = setTimeout(() => {
        const socket = socketRef.current;
        if (socket?.readyState === WebSocket.OPEN) sendHostSync(socket);
      }, 180);
    });
  }, [isHost]);

  return null;
}

function sendHostSync(socket: WebSocket) {
  const state = usePlaybackStore.getState();
  const song = state.current ? trackToSong(state.current, state.duration) : null;
  socket.send(
    JSON.stringify({
      type: "sync",
      payload: {
        song,
        queue: state.queue.map((track, index) => trackToSong(track, index === state.currentIndex ? state.duration : track.duration)),
        is_playing: state.isPlaying,
        position_ms: Math.round(state.position * 1000),
      },
    }),
  );
}
