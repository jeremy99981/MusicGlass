import { resumeAudioContext } from "./audio-context";

type PlaybackAudioSession = {
  type: string;
};

type NavigatorWithAudioSession = Navigator & {
  audioSession?: PlaybackAudioSession;
};

export async function activatePlaybackAudioSession(audio?: HTMLMediaElement, volume?: number) {
  if (audio) {
    audio.defaultMuted = false;
    audio.muted = false;
    if (typeof volume === "number" && Number.isFinite(volume)) audio.volume = volume;
  }

  if (typeof navigator !== "undefined") {
    const audioSession = (navigator as NavigatorWithAudioSession).audioSession;
    if (audioSession) {
      try {
        audioSession.type = "playback";
      } catch {
        // Older WebKit builds expose a read-only or incomplete Audio Session API.
      }
    }
  }

  if (audio) await resumeAudioContext(audio);
}
