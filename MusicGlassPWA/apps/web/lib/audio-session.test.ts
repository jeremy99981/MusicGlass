import { afterEach, describe, expect, it } from "vitest";
import { activatePlaybackAudioSession } from "./audio-session";

describe("activatePlaybackAudioSession", () => {
  afterEach(() => {
    delete (navigator as Navigator & { audioSession?: unknown }).audioSession;
  });

  it("selects the iOS playback category and unmutes the media element", () => {
    const session = { type: "ambient" };
    Object.defineProperty(navigator, "audioSession", { configurable: true, value: session });
    const audio = document.createElement("audio");
    audio.muted = true;
    audio.defaultMuted = true;

    activatePlaybackAudioSession(audio, 0.72);

    expect(session.type).toBe("playback");
    expect(audio.muted).toBe(false);
    expect(audio.defaultMuted).toBe(false);
    expect(audio.volume).toBe(0.72);
  });

  it("remains safe when the Audio Session API is unavailable", () => {
    const audio = document.createElement("audio");
    expect(() => activatePlaybackAudioSession(audio, 0.5)).not.toThrow();
  });
});
