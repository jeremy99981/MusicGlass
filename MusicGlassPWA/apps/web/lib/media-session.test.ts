import { describe, expect, it, vi } from "vitest";
import {
  clearMediaSessionActions,
  configureMediaSessionActions,
  prefersTrackNavigationOnly,
} from "./media-session";

describe("media session actions", () => {
  it("prioritizes playlist previous and next over ±10s seek actions", () => {
    const handlers = new Map<string, MediaSessionActionHandler | null>();
    const mediaSession = {
      setActionHandler: vi.fn((action: string, handler: MediaSessionActionHandler | null) => {
        handlers.set(action, handler);
      }),
      playbackState: "none" as MediaSessionPlaybackState,
    };
    const play = vi.fn();
    const pause = vi.fn();
    const next = vi.fn();
    const previous = vi.fn();
    const seekTo = vi.fn();

    configureMediaSessionActions({ mediaSession, play, pause, next, previous, seekTo });

    handlers.get("nexttrack")?.({ action: "nexttrack" });
    handlers.get("previoustrack")?.({ action: "previoustrack" });
    handlers.get("seekto")?.({ action: "seekto", seekTime: 42 });

    expect(handlers.get("seekforward")).toBeNull();
    expect(handlers.get("seekbackward")).toBeNull();
    expect(next).toHaveBeenCalledTimes(1);
    expect(previous).toHaveBeenCalledTimes(1);
    expect(seekTo).toHaveBeenCalledWith(42, false);
  });

  it("bounds seek times and ignores non-finite values", () => {
    const handlers = new Map<string, MediaSessionActionHandler | null>();
    const mediaSession = {
      setActionHandler: vi.fn((action: string, handler: MediaSessionActionHandler | null) => handlers.set(action, handler)),
    };
    const seekTo = vi.fn();

    configureMediaSessionActions({
      mediaSession,
      play: vi.fn(),
      pause: vi.fn(),
      next: vi.fn(),
      previous: vi.fn(),
      seekTo,
    });

    handlers.get("seekto")?.({ action: "seekto", seekTime: -12, fastSeek: true });
    handlers.get("seekto")?.({ action: "seekto", seekTime: Number.NaN });
    handlers.get("seekto")?.({ action: "seekto", seekTime: Number.POSITIVE_INFINITY });

    expect(seekTo).toHaveBeenCalledOnce();
    expect(seekTo).toHaveBeenCalledWith(0, true);
  });

  it("removes every seek action for Apple's track-navigation profile", () => {
    const handlers = new Map<string, MediaSessionActionHandler | null>();
    const mediaSession = {
      setActionHandler: vi.fn((action: string, handler: MediaSessionActionHandler | null) => handlers.set(action, handler)),
    };

    configureMediaSessionActions({
      mediaSession,
      play: vi.fn(),
      pause: vi.fn(),
      next: vi.fn(),
      previous: vi.fn(),
      seekTo: vi.fn(),
      enableSeekTo: false,
    });

    expect(handlers.get("seekbackward")).toBeNull();
    expect(handlers.get("seekforward")).toBeNull();
    expect(handlers.get("seekto")).toBeNull();
    expect(handlers.get("previoustrack")).toBeTypeOf("function");
    expect(handlers.get("nexttrack")).toBeTypeOf("function");
  });

  it("delegates play and pause to WebKit while keeping track navigation", () => {
    const handlers = new Map<string, MediaSessionActionHandler | null>();
    const mediaSession = {
      setActionHandler: vi.fn((action: string, handler: MediaSessionActionHandler | null) => handlers.set(action, handler)),
    };

    configureMediaSessionActions({
      mediaSession,
      play: vi.fn(),
      pause: vi.fn(),
      next: vi.fn(),
      previous: vi.fn(),
      seekTo: vi.fn(),
      enableSeekTo: false,
      enableTransportHandlers: false,
    });

    expect(handlers.get("play")).toBeNull();
    expect(handlers.get("pause")).toBeNull();
    expect(handlers.get("previoustrack")).toBeTypeOf("function");
    expect(handlers.get("nexttrack")).toBeTypeOf("function");
  });

  it("detects iPhone and desktop-UA iPad without changing Android or Mac desktop", () => {
    expect(prefersTrackNavigationOnly({ userAgent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X)" })).toBe(true);
    expect(prefersTrackNavigationOnly({ userAgent: "Mozilla/5.0 (Macintosh)", platform: "MacIntel", maxTouchPoints: 5 })).toBe(true);
    expect(prefersTrackNavigationOnly({ userAgent: "Mozilla/5.0 (Linux; Android 15)", platform: "Linux armv8l", maxTouchPoints: 5 })).toBe(false);
    expect(prefersTrackNavigationOnly({ userAgent: "Mozilla/5.0 (Macintosh)", platform: "MacIntel", maxTouchPoints: 0 })).toBe(false);
  });

  it("publishes track navigation after the seek command updates", () => {
    const mediaSession = { setActionHandler: vi.fn() };

    configureMediaSessionActions({
      mediaSession,
      play: vi.fn(),
      pause: vi.fn(),
      next: vi.fn(),
      previous: vi.fn(),
      seekTo: vi.fn(),
      enableSeekTo: false,
    });

    const actions = mediaSession.setActionHandler.mock.calls.map(([action]) => action);
    expect(actions.slice(0, 3)).toEqual(["seekbackward", "seekforward", "seekto"]);
    expect(actions.slice(-2)).toEqual(["previoustrack", "nexttrack"]);
  });

  it("does not claim playback changed before the media element confirms it", () => {
    const handlers = new Map<string, MediaSessionActionHandler | null>();
    const mediaSession = {
      setActionHandler: vi.fn((action: string, handler: MediaSessionActionHandler | null) => handlers.set(action, handler)),
      playbackState: "paused" as MediaSessionPlaybackState,
    };

    configureMediaSessionActions({
      mediaSession,
      play: vi.fn().mockRejectedValue(new Error("resume failed")),
      pause: vi.fn(),
      next: vi.fn(),
      previous: vi.fn(),
      seekTo: vi.fn(),
    });

    handlers.get("play")?.({ action: "play" });
    expect(mediaSession.playbackState).toBe("paused");
  });

  it("keeps registering supported actions when another action is rejected", () => {
    const handlers = new Map<string, MediaSessionActionHandler | null>();
    const mediaSession = {
      setActionHandler: vi.fn((action: string, handler: MediaSessionActionHandler | null) => {
        if (action === "nexttrack") throw new TypeError("unsupported");
        handlers.set(action, handler);
      }),
    };
    const previous = vi.fn(() => {
      throw new Error("queue changed");
    });
    const seekTo = vi.fn();

    configureMediaSessionActions({
      mediaSession,
      play: vi.fn(),
      pause: vi.fn(),
      next: vi.fn(),
      previous,
      seekTo,
    });

    expect(() => handlers.get("previoustrack")?.({ action: "previoustrack" })).not.toThrow();
    handlers.get("seekto")?.({ action: "seekto", seekTime: 18 });

    expect(previous).toHaveBeenCalledOnce();
    expect(seekTo).toHaveBeenCalledWith(18, false);
  });

  it("clears all registered actions", () => {
    const mediaSession = {
      setActionHandler: vi.fn(),
    };

    clearMediaSessionActions(mediaSession);

    expect(mediaSession.setActionHandler).toHaveBeenCalledWith("seekforward", null);
    expect(mediaSession.setActionHandler).toHaveBeenCalledWith("seekbackward", null);
    expect(mediaSession.setActionHandler).toHaveBeenCalledWith("nexttrack", null);
    expect(mediaSession.setActionHandler).toHaveBeenCalledWith("previoustrack", null);
  });
});
