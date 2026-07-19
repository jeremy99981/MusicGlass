import React from "react";
import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { addLibraryLike } from "@/lib/api";
import { usePlaybackStore } from "@/store/playback-store";
import { useSharedSessionStore } from "@/store/shared-session-store";
import { MiniPlayer } from "./mini-player";

vi.mock("@/lib/api", () => ({
  addLibraryLike: vi.fn().mockResolvedValue(undefined),
}));

const testTrack = {
  id: "track-1",
  title: "Feu de bois",
  artist: "Damso",
  album: "Lithopedion",
  artwork: "https://example.com/art.jpg",
  duration: 184,
  accent: "#263443",
};

const nextTrack = {
  ...testTrack,
  id: "track-2",
  title: "Smog",
};

describe("MiniPlayer", () => {
  afterEach(() => {
    cleanup();
  });

  beforeEach(() => {
    localStorage.clear();
    vi.clearAllMocks();
    usePlaybackStore.setState({
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
    });
    useSharedSessionStore.setState({
      code: null,
      status: "disconnected",
      isHost: false,
      participants: [],
      error: null,
    });
  });

  it("does not render without a current track", () => {
    render(<MiniPlayer />);
    expect(screen.queryByRole("region", { name: "Lecteur audio" })).not.toBeInTheDocument();
  });

  it("renders track details and complete transport controls", () => {
    usePlaybackStore.setState({
      current: testTrack,
      queue: [testTrack, nextTrack],
      currentIndex: 0,
      isPlaying: true,
      position: 62,
      duration: testTrack.duration,
    });

    render(<MiniPlayer />);

    const player = screen.getByRole("region", { name: "Lecteur audio" });
    expect(within(player).getByText("Feu de bois")).toBeInTheDocument();
    expect(within(player).getByText("Damso · Lithopedion")).toBeInTheDocument();
    expect(within(player).getByText("1:02")).toBeInTheDocument();
    expect(within(player).getByText("3:04")).toBeInTheDocument();
    expect(within(player).getByRole("button", { name: "Précédent" })).toBeEnabled();
    expect(within(player).getByRole("button", { name: "Suivant" })).toBeEnabled();
    expect(within(player).getByRole("slider", { name: "Position de lecture" })).toHaveValue("62");
    expect(within(player).getByRole("button", { name: /file d’attente, 1 titre à suivre/i })).toBeEnabled();

    fireEvent.click(within(player).getByRole("button", { name: "Pause" }));
    expect(usePlaybackStore.getState().isPlaying).toBe(false);
  });

  it("seeks and opens the queue", () => {
    usePlaybackStore.setState({
      current: testTrack,
      queue: [testTrack, nextTrack],
      currentIndex: 0,
      duration: testTrack.duration,
    });

    render(<MiniPlayer />);
    const player = screen.getByRole("region", { name: "Lecteur audio" });

    fireEvent.change(within(player).getByRole("slider", { name: "Position de lecture" }), {
      target: { value: "90" },
    });
    expect(usePlaybackStore.getState().requestedPosition).toBe(90);

    fireEvent.click(within(player).getByRole("button", { name: /ouvrir la file d’attente/i }));
    expect(usePlaybackStore.getState().queueOpen).toBe(true);
  });

  it("likes the current track with optimistic feedback", async () => {
    usePlaybackStore.setState({ current: testTrack, queue: [testTrack], currentIndex: 0 });

    render(<MiniPlayer />);
    const likeButton = screen.getByRole("button", { name: "Aimer ce titre" });
    fireEvent.click(likeButton);

    expect(screen.getByRole("button", { name: "Titre aimé" })).toHaveAttribute("aria-pressed", "true");
    await waitFor(() => expect(addLibraryLike).toHaveBeenCalledWith(testTrack));
  });

  it("keeps shared-session guest playback locked without blocking local actions", () => {
    usePlaybackStore.setState({
      current: testTrack,
      queue: [testTrack, nextTrack],
      currentIndex: 0,
      duration: testTrack.duration,
    });
    useSharedSessionStore.setState({ code: "ABCD", isHost: false });

    render(<MiniPlayer />);
    const player = screen.getByRole("region", { name: "Lecteur audio" });

    expect(within(player).getByRole("button", { name: "Précédent" })).toBeDisabled();
    expect(within(player).getByRole("button", { name: "Contrôles réservés à l’hôte" })).toBeDisabled();
    expect(within(player).getByRole("button", { name: "Suivant" })).toBeDisabled();
    expect(within(player).getByRole("slider", { name: "Position de lecture" })).toBeDisabled();
    expect(within(player).getByRole("button", { name: /ouvrir la file d’attente/i })).toBeEnabled();
    expect(within(player).getByRole("button", { name: "Aimer ce titre" })).toBeEnabled();
  });

  it("opens the full player when the track area is clicked", () => {
    usePlaybackStore.setState({ current: testTrack, queue: [testTrack], currentIndex: 0 });

    render(<MiniPlayer />);
    fireEvent.click(screen.getByRole("button", { name: /ouvrir le lecteur pour feu de bois/i }));

    expect(usePlaybackStore.getState().playerOpen).toBe(true);
  });

  it("uses the artwork fallback when the cover cannot load", () => {
    usePlaybackStore.setState({ current: testTrack, queue: [testTrack], currentIndex: 0 });

    render(<MiniPlayer />);
    const player = screen.getByRole("region", { name: "Lecteur audio" });
    const image = player.querySelector("img");
    expect(image).not.toBeNull();

    fireEvent.error(image as HTMLImageElement);

    expect(image).toHaveStyle({ display: "none" });
    expect(image?.parentElement).toHaveClass("artwork-fallback");
  });
});
