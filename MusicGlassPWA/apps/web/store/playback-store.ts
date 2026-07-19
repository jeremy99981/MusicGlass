"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";
import { uniqueTracks, type Track } from "@/lib/catalog";

type RepeatMode = "off" | "all" | "one";
export type PlaybackStatus = "idle" | "loading" | "buffering" | "playing" | "paused" | "error";

type PlaybackState = {
  current: Track | null;
  queue: Track[];
  currentIndex: number;
  isPlaying: boolean;
  position: number;
  duration: number;
  requestedPosition: number | null;
  status: PlaybackStatus;
  error: string | null;
  volume: number;
  shuffle: boolean;
  repeat: RepeatMode;
  playerOpen: boolean;
  queueOpen: boolean;
  isQueueLoading: boolean;
  queueError: string | null;
  playTrack: (track: Track, queue?: Track[]) => void;
  setPlaying: (value: boolean) => void;
  setPosition: (value: number) => void;
  setDuration: (value: number) => void;
  setStatus: (status: PlaybackStatus, error?: string | null) => void;
  seekTo: (value: number) => void;
  clearSeek: () => void;
  setVolume: (value: number) => void;
  setQueueLoading: (value: boolean) => void;
  setQueueError: (value: string | null) => void;
  appendToQueue: (tracks: Track[]) => void;
  playQueueIndex: (index: number) => void;
  removeFromQueue: (index: number) => void;
  moveQueueItem: (fromIndex: number, toIndex: number) => void;
  applyRemotePlayback: (payload: { current: Track; queue: Track[]; isPlaying: boolean; position: number }) => void;
  next: () => void;
  previous: () => void;
  toggleShuffle: () => void;
  cycleRepeat: () => void;
  setPlayerOpen: (value: boolean) => void;
  setQueueOpen: (value: boolean) => void;
};

function clampPosition(position: number, duration: number) {
  const safePosition = Number.isFinite(position) ? Math.max(0, position) : 0;
  return duration > 0 ? Math.min(safePosition, duration) : safePosition;
}

export const usePlaybackStore = create<PlaybackState>()(
  persist(
    (set, get) => ({
      current: null,
      queue: [],
      currentIndex: -1,
      isPlaying: false,
      position: 0,
      duration: 0,
      requestedPosition: null,
      status: "idle",
      error: null,
      volume: 0.85,
      shuffle: false,
      repeat: "off",
      playerOpen: false,
      queueOpen: false,
      isQueueLoading: false,
      queueError: null,
      playTrack: (track, queue = [track]) => {
        const normalized = uniqueTracks(queue.some((item) => item.id === track.id) ? queue : [track, ...queue]);
        const currentIndex = Math.max(0, normalized.findIndex((item) => item.id === track.id));
        const selected = normalized[currentIndex];
        set({
          current: selected,
          queue: normalized,
          currentIndex,
          position: 0,
          duration: selected.duration,
          requestedPosition: 0,
          isPlaying: true,
          status: "loading",
          error: null,
          queueError: null,
        });
      },
      setPlaying: (isPlaying) => set({ isPlaying, status: isPlaying ? "loading" : "paused", error: null }),
      setPosition: (position) => set((state) => ({ position: clampPosition(position, state.duration) })),
      setDuration: (duration) => set((state) => {
        const safeDuration = Number.isFinite(duration) && duration > 0 ? duration : 0;
        return { duration: safeDuration, position: clampPosition(state.position, safeDuration) };
      }),
      setStatus: (status, error = null) => set({ status, error }),
      seekTo: (position) => set({ position, requestedPosition: position }),
      clearSeek: () => set({ requestedPosition: null }),
      setVolume: (volume) => set({ volume }),
      setQueueLoading: (isQueueLoading) => set({ isQueueLoading }),
      setQueueError: (queueError) => set({ queueError }),
      appendToQueue: (tracks) =>
        set((state) => ({
          queue: uniqueTracks([...state.queue, ...tracks]),
          queueError: null,
        })),
      playQueueIndex: (index) => {
        const state = get();
        const track = state.queue[index];
        if (!track) return;
        set({
          currentIndex: index,
          current: track,
          position: 0,
          duration: track.duration,
          requestedPosition: 0,
          isPlaying: true,
          status: "loading",
          error: null,
        });
      },
      removeFromQueue: (index) => {
        const state = get();
        if (index < 0 || index >= state.queue.length || index === state.currentIndex) return;
        const queue = state.queue.filter((_, itemIndex) => itemIndex !== index);
        const currentIndex = index < state.currentIndex ? state.currentIndex - 1 : state.currentIndex;
        set({ queue, currentIndex });
      },
      moveQueueItem: (fromIndex, toIndex) => {
        const state = get();
        if (
          fromIndex < 0 ||
          fromIndex >= state.queue.length ||
          toIndex < 0 ||
          toIndex >= state.queue.length ||
          fromIndex === toIndex ||
          fromIndex === state.currentIndex ||
          toIndex === state.currentIndex
        ) {
          return;
        }

        const queue = [...state.queue];
        const [item] = queue.splice(fromIndex, 1);
        queue.splice(toIndex, 0, item);
        const currentId = state.current?.id;
        const currentIndex = Math.max(0, queue.findIndex((track) => track.id === currentId));
        set({ queue, currentIndex });
      },
      applyRemotePlayback: ({ current, queue, isPlaying, position }) => {
        const previous = get();
        const normalized = uniqueTracks(queue.length ? queue : [current]);
        const currentIndex = Math.max(0, normalized.findIndex((item) => item.id === current.id));
        const selected = normalized[currentIndex];
        const sameTrack = previous.current?.id === selected.id;
        const duration = selected.duration > 0 ? selected.duration : sameTrack ? previous.duration : 0;
        const safePosition = clampPosition(position, duration);
        const shouldSeek = !sameTrack || Math.abs(previous.position - safePosition) > 1.5;
        set({
          current: selected,
          queue: normalized,
          currentIndex,
          isPlaying,
          position: safePosition,
          requestedPosition: shouldSeek ? safePosition : previous.requestedPosition,
          duration,
          status: isPlaying ? "loading" : "paused",
          error: null,
        });
      },
      next: () => {
        const state = get();
        if (!state.queue.length) return;
        if (state.repeat === "one") {
          set({ position: 0, requestedPosition: 0, isPlaying: true, status: "loading", error: null });
          return;
        }
        const atEnd = state.currentIndex >= state.queue.length - 1;
        // AutoMix normally replenishes well before this branch. Wrapping is the
        // offline safety net that keeps playback continuous during a network gap.
        const nextIndex = atEnd ? 0 : state.currentIndex + 1;
        set({ currentIndex: nextIndex, current: state.queue[nextIndex], position: 0, duration: state.queue[nextIndex].duration, requestedPosition: 0, isPlaying: true, status: "loading", error: null });
      },
      previous: () => {
        const state = get();
        if (state.position > 4) return set({ position: 0, requestedPosition: 0 });
        const index = state.currentIndex <= 0 ? state.queue.length - 1 : state.currentIndex - 1;
        if (index >= 0) set({ currentIndex: index, current: state.queue[index], position: 0, duration: state.queue[index].duration, requestedPosition: 0, isPlaying: true, status: "loading", error: null });
      },
      toggleShuffle: () => set((state) => ({ shuffle: !state.shuffle })),
      cycleRepeat: () => set((state) => ({ repeat: state.repeat === "off" ? "all" : state.repeat === "all" ? "one" : "off" })),
      setPlayerOpen: (playerOpen) => set({ playerOpen }),
      setQueueOpen: (queueOpen) => set({ queueOpen }),
    }),
    {
      // v2 discards queues that were previously populated with raw search
      // results instead of YouTube Music AutoMix recommendations.
      name: "musicglass-playback-v2",
      partialize: (state) => ({ current: state.current, queue: state.queue, currentIndex: state.currentIndex, position: state.position, duration: state.duration, volume: state.volume, shuffle: state.shuffle, repeat: state.repeat, playerOpen: state.playerOpen, queueOpen: false, isPlaying: false, status: "paused" }),
    },
  ),
);
