import { afterEach, describe, expect, it } from "vitest";
import { useSharedSessionStore } from "./shared-session-store";

describe("shared session store", () => {
  afterEach(() => {
    useSharedSessionStore.getState().reset();
    localStorage.clear();
  });

  it("updates participants from websocket joined and left events", () => {
    const host = { user_id: 1, client_id: "host-web", name: "Host", is_host: true };
    const guest = { user_id: 2, client_id: "guest-web", name: "Guest", is_host: false };

    useSharedSessionStore.getState().setParticipants([host]);
    useSharedSessionStore.getState().addParticipant(guest);
    useSharedSessionStore.getState().addParticipant(guest);

    expect(useSharedSessionStore.getState().participants).toEqual([host, guest]);

    useSharedSessionStore.getState().removeParticipant(guest);

    expect(useSharedSessionStore.getState().participants).toEqual([host]);
  });
});
