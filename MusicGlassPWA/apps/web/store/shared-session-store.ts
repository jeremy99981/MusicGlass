"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";

export type SharedParticipant = {
  client_id?: string;
  user_id: number;
  name: string;
  is_host: boolean;
};

type ConnectionStatus = "disconnected" | "connecting" | "connected" | "error";

type SharedSessionState = {
  code: string | null;
  status: ConnectionStatus;
  isHost: boolean;
  participants: SharedParticipant[];
  error: string | null;
  setSession: (value: { code: string; isHost: boolean }) => void;
  setStatus: (status: ConnectionStatus) => void;
  setParticipants: (participants: SharedParticipant[]) => void;
  addParticipant: (participant: SharedParticipant) => void;
  removeParticipant: (participant: SharedParticipant) => void;
  setError: (error: string | null) => void;
  reset: () => void;
};

export const useSharedSessionStore = create<SharedSessionState>()(
  persist(
    (set) => ({
      code: null,
      status: "disconnected",
      isHost: false,
      participants: [],
      error: null,
      setSession: ({ code, isHost }) =>
        set({
          code: code.trim().toUpperCase(),
          isHost,
          status: "connecting",
          error: null,
          participants: [],
        }),
      setStatus: (status) => set({ status }),
      setParticipants: (participants) => set({ participants }),
      addParticipant: (participant) =>
        set((state) => {
          const exists = state.participants.some(
            (current) =>
              current.client_id === participant.client_id ||
              (!current.client_id && !participant.client_id && current.user_id === participant.user_id),
          );
          return exists ? state : { participants: [...state.participants, participant] };
        }),
      removeParticipant: (participant) =>
        set((state) => ({
          participants: state.participants.filter((current) => {
            if (participant.client_id) return current.client_id !== participant.client_id;
            return current.user_id !== participant.user_id;
          }),
        })),
      setError: (error) => set((state) => ({ error, status: error ? "error" : state.status })),
      reset: () =>
        set({
          code: null,
          status: "disconnected",
          isHost: false,
          participants: [],
          error: null,
        }),
    }),
    {
      name: "musicglass-shared-session-v1",
      partialize: (state) => ({ code: state.code, isHost: state.isHost }),
      onRehydrateStorage: () => (state) => {
        state?.setStatus(state.code ? "connecting" : "disconnected");
      },
    },
  ),
);
