import { beforeEach, describe, expect, it } from "vitest";
import { demoTracks } from "@/lib/catalog";
import { usePlaybackStore } from "./playback-store";

describe("playback store", () => {
  beforeEach(() => {
    localStorage.clear();
    usePlaybackStore.setState({ current: null, queue: [], currentIndex: -1, isPlaying: false, position: 0, duration: 0, requestedPosition: null, status: "idle", error: null, shuffle: false, repeat: "off", playerOpen: false, queueOpen: false, isQueueLoading: false, queueError: null });
  });

  it("starts a selected track with its queue", () => {
    usePlaybackStore.getState().playTrack(demoTracks[1], demoTracks);
    const state = usePlaybackStore.getState();
    expect(state.current?.id).toBe("airplanes");
    expect(state.currentIndex).toBe(1);
    expect(state.isPlaying).toBe(true);
    expect(state.status).toBe("loading");
  });

  it("stores the normalized queue item as the current track", () => {
    usePlaybackStore.getState().playTrack({
      id: "normalized",
      title: "Ziak - FENG SHUI",
      artist: "Vidéo",
      album: "",
      artwork: "",
      duration: 160,
      accent: "#000000",
    });

    const state = usePlaybackStore.getState();
    expect(state.current).toBe(state.queue[0]);
    expect(state.current?.artist).toBe("Ziak");
  });

  it("wraps at the queue end when repeat is off so continuous playback never stops", () => {
    usePlaybackStore.getState().playTrack(demoTracks.at(-1)!, demoTracks);
    usePlaybackStore.getState().next();
    expect(usePlaybackStore.getState().current?.id).toBe(demoTracks[0].id);
    expect(usePlaybackStore.getState().isPlaying).toBe(true);
  });

  it("wraps at the queue end when repeat all is enabled", () => {
    usePlaybackStore.getState().playTrack(demoTracks.at(-1)!, demoTracks);
    usePlaybackStore.setState({ repeat: "all" });
    usePlaybackStore.getState().next();
    expect(usePlaybackStore.getState().current?.id).toBe(demoTracks[0].id);
  });

  it("restarts the same source when repeat one is enabled", () => {
    usePlaybackStore.getState().playTrack(demoTracks[0], demoTracks);
    usePlaybackStore.setState({ repeat: "one", position: 23, requestedPosition: null });
    usePlaybackStore.getState().next();
    expect(usePlaybackStore.getState().current?.id).toBe(demoTracks[0].id);
    expect(usePlaybackStore.getState().requestedPosition).toBe(0);
  });

  it("records an explicit seek request for the audio engine", () => {
    usePlaybackStore.getState().seekTo(12);
    expect(usePlaybackStore.getState().position).toBe(12);
    expect(usePlaybackStore.getState().requestedPosition).toBe(12);
  });

  it("appends unique recommendations to the queue", () => {
    usePlaybackStore.getState().playTrack(demoTracks[0], [demoTracks[0]]);
    usePlaybackStore.getState().appendToQueue([demoTracks[0], demoTracks[1], demoTracks[2]]);

    expect(usePlaybackStore.getState().queue.map((track) => track.id)).toEqual([
      demoTracks[0].id,
      demoTracks[1].id,
      demoTracks[2].id,
    ]);
  });

  it("plays, removes and reorders upcoming queue items", () => {
    usePlaybackStore.getState().playTrack(demoTracks[0], demoTracks.slice(0, 4));
    usePlaybackStore.getState().playQueueIndex(2);
    expect(usePlaybackStore.getState().current?.id).toBe(demoTracks[2].id);
    expect(usePlaybackStore.getState().currentIndex).toBe(2);

    usePlaybackStore.getState().removeFromQueue(1);
    expect(usePlaybackStore.getState().queue.map((track) => track.id)).toEqual([
      demoTracks[0].id,
      demoTracks[2].id,
      demoTracks[3].id,
    ]);
    expect(usePlaybackStore.getState().currentIndex).toBe(1);

    usePlaybackStore.getState().moveQueueItem(2, 0);
    expect(usePlaybackStore.getState().queue.map((track) => track.id)).toEqual([
      demoTracks[3].id,
      demoTracks[0].id,
      demoTracks[2].id,
    ]);
    expect(usePlaybackStore.getState().currentIndex).toBe(2);
  });

  it("applies a remote shared-session snapshot atomically", () => {
    usePlaybackStore.getState().applyRemotePlayback({
      current: demoTracks[2],
      queue: demoTracks,
      isPlaying: true,
      position: 42,
    });

    const state = usePlaybackStore.getState();
    expect(state.current?.id).toBe("feu-de-bois");
    expect(state.currentIndex).toBe(2);
    expect(state.isPlaying).toBe(true);
    expect(state.position).toBe(demoTracks[2].duration);
    expect(state.requestedPosition).toBe(demoTracks[2].duration);
  });

  it("does not request a seek for harmless remote clock drift", () => {
    usePlaybackStore.getState().playTrack(demoTracks[0], demoTracks);
    usePlaybackStore.setState({ position: 12, requestedPosition: null });
    usePlaybackStore.getState().applyRemotePlayback({
      current: demoTracks[0],
      queue: demoTracks,
      isPlaying: true,
      position: 12.4,
    });
    expect(usePlaybackStore.getState().requestedPosition).toBeNull();
  });
});
