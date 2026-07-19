import { describe, expect, it, vi } from "vitest";
import { isActuallyProgressing, resumeMediaElement } from "./audio-resume";

function audioFixture() {
  const audio = document.createElement("audio");
  let paused = true;
  Object.defineProperty(audio, "paused", { configurable: true, get: () => paused });
  Object.defineProperty(audio, "duration", { configurable: true, value: 180 });
  Object.defineProperty(audio, "seekable", {
    configurable: true,
    value: { length: 1, start: () => 0, end: () => 180 },
  });
  audio.currentTime = 42;
  const pause = vi.spyOn(audio, "pause").mockImplementation(() => {
    paused = true;
  });
  const setPlaying = () => {
    paused = false;
  };
  return { audio, pause, setPlaying };
}

describe("resumeMediaElement", () => {
  it("keeps a normal play instant and never reloads a progressing source", async () => {
    const { audio, setPlaying } = audioFixture();
    const load = vi.spyOn(audio, "load");
    const refreshSource = vi.fn();
    const play = vi.spyOn(audio, "play").mockImplementation(async () => {
      setPlaying();
      window.setTimeout(() => { audio.currentTime += 0.25; }, 0);
    });

    await expect(resumeMediaElement({
      audio,
      fallbackPosition: 0,
      refreshSource,
      progressionTimeoutMs: 5,
    })).resolves.toBe("resumed");

    expect(play).toHaveBeenCalledOnce();
    expect(load).not.toHaveBeenCalled();
    expect(refreshSource).not.toHaveBeenCalled();
  });

  it("reloads once after play resolves without real progression and restores state", async () => {
    const { audio, pause, setPlaying } = audioFixture();
    audio.volume = 0.37;
    audio.muted = true;
    audio.playbackRate = 1.25;
    const recoveryEvents: string[] = [];
    let playCount = 0;
    const play = vi.spyOn(audio, "play").mockImplementation(async () => {
      playCount += 1;
      setPlaying();
      if (playCount === 2) window.setTimeout(() => { audio.currentTime += 0.3; }, 0);
    });
    const load = vi.spyOn(audio, "load").mockImplementation(() => {
      audio.dispatchEvent(new Event("loadedmetadata"));
    });

    await expect(resumeMediaElement({
      audio,
      fallbackPosition: 12,
      refreshSource: vi.fn().mockResolvedValue("/api/v2/media/stream/track?resume=1"),
      progressionTimeoutMs: 5,
      onRecoveryEvent: (event) => recoveryEvents.push(event),
    })).resolves.toBe("reloaded");

    expect(play).toHaveBeenCalledTimes(2);
    expect(pause).toHaveBeenCalledOnce();
    expect(load).toHaveBeenCalledOnce();
    expect(audio.src).toContain("resume=1");
    expect(audio.currentTime).toBeGreaterThan(42.1);
    expect(audio.volume).toBe(0.37);
    expect(audio.muted).toBe(true);
    expect(audio.playbackRate).toBe(1.25);
    expect(recoveryEvents).toEqual(["audio_recovery_started", "audio_recovery_succeeded"]);
  });

  it("does not reload when the initial play rejects", async () => {
    const { audio } = audioFixture();
    const error = new DOMException("play rejected", "NotAllowedError");
    vi.spyOn(audio, "play").mockRejectedValue(error);
    const load = vi.spyOn(audio, "load");
    const refreshSource = vi.fn();

    await expect(resumeMediaElement({
      audio,
      fallbackPosition: 0,
      refreshSource,
      progressionTimeoutMs: 1,
    })).rejects.toBe(error);

    expect(load).not.toHaveBeenCalled();
    expect(refreshSource).not.toHaveBeenCalled();
  });

  it("stops after one failed recovery attempt", async () => {
    const { audio, setPlaying } = audioFixture();
    const events: string[] = [];
    const play = vi.spyOn(audio, "play").mockImplementation(async () => setPlaying());
    const load = vi.spyOn(audio, "load").mockImplementation(() => {
      audio.dispatchEvent(new Event("canplay"));
    });

    await expect(resumeMediaElement({
      audio,
      fallbackPosition: 0,
      refreshSource: () => "/api/v2/media/stream/track?resume=failed",
      progressionTimeoutMs: 2,
      onRecoveryEvent: (event) => events.push(event),
    })).resolves.toBe("failed");

    expect(play).toHaveBeenCalledTimes(2);
    expect(load).toHaveBeenCalledOnce();
    expect(events).toEqual(["audio_recovery_started", "audio_recovery_failed"]);
  });

  it("cancels recovery when the track changes", async () => {
    const { audio, setPlaying } = audioFixture();
    vi.spyOn(audio, "play").mockImplementation(async () => setPlaying());
    let current = true;

    await expect(resumeMediaElement({
      audio,
      fallbackPosition: 0,
      refreshSource: async () => {
        current = false;
        return "/api/v2/media/stream/old-track";
      },
      isCurrent: () => current,
      progressionTimeoutMs: 2,
    })).resolves.toBe("cancelled");

    expect(audio.getAttribute("src")).toBeNull();
  });
});

describe("isActuallyProgressing", () => {
  it("requires both an active element and time progression", async () => {
    const { audio, setPlaying } = audioFixture();
    setPlaying();
    const initialPosition = audio.currentTime;
    window.setTimeout(() => { audio.currentTime += 0.2; }, 0);
    await expect(isActuallyProgressing(audio, initialPosition, 5)).resolves.toBe(true);
  });
});
