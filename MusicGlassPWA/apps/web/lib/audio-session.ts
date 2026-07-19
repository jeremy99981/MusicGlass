type PlaybackAudioSession = {
  type: string;
};

type NavigatorWithAudioSession = Navigator & {
  audioSession?: PlaybackAudioSession;
};

export function activatePlaybackAudioSession(audio?: HTMLMediaElement, volume?: number) {
  if (audio) {
    audio.defaultMuted = false;
    audio.muted = false;
    if (typeof volume === "number" && Number.isFinite(volume)) audio.volume = volume;
  }

  if (typeof navigator === "undefined") return;
  const audioSession = (navigator as NavigatorWithAudioSession).audioSession;
  if (!audioSession) return;

  try {
    audioSession.type = "playback";
  } catch {
    // Older WebKit builds expose a read-only or incomplete Audio Session API.
  }
}
