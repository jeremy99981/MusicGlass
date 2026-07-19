type AudioRecoveryEvent = "audio_recovery_started" | "audio_recovery_succeeded" | "audio_recovery_failed";

type ResumeMediaElementInput = {
  audio: HTMLAudioElement;
  fallbackPosition: number;
  refreshSource: () => string | Promise<string>;
  isCurrent?: () => boolean;
  metadataTimeoutMs?: number;
  progressionTimeoutMs?: number;
  minimumProgressSeconds?: number;
  onRecoveryEvent?: (event: AudioRecoveryEvent, reason?: string) => void;
};

export type ResumeMediaElementResult = "resumed" | "reloaded" | "failed" | "cancelled";

type AudioSnapshot = {
  src: string;
  currentTime: number;
  playbackRate: number;
  volume: number;
  muted: boolean;
};

function delay(milliseconds: number) {
  return new Promise<void>((resolve) => window.setTimeout(resolve, milliseconds));
}

function waitForFreshMedia(audio: HTMLAudioElement, timeoutMs: number) {
  return new Promise<void>((resolve, reject) => {
    const cleanup = () => {
      window.clearTimeout(timeout);
      audio.removeEventListener("loadedmetadata", onReady);
      audio.removeEventListener("canplay", onReady);
      audio.removeEventListener("error", onError);
    };
    const onReady = () => {
      cleanup();
      resolve();
    };
    const onError = () => {
      cleanup();
      reject(new Error("The refreshed audio source could not be loaded."));
    };
    const timeout = window.setTimeout(() => {
      cleanup();
      reject(new Error("Timed out while refreshing the audio source."));
    }, timeoutMs);

    audio.addEventListener("loadedmetadata", onReady, { once: true });
    audio.addEventListener("canplay", onReady, { once: true });
    audio.addEventListener("error", onError, { once: true });
  });
}

export async function isActuallyProgressing(
  audio: HTMLAudioElement,
  positionBeforePlay: number,
  timeoutMs = 1300,
  minimumProgressSeconds = 0.1,
) {
  await delay(timeoutMs);
  return !audio.paused
    && !audio.ended
    && audio.currentTime > positionBeforePlay + minimumProgressSeconds;
}

function seekablePosition(audio: HTMLAudioElement, requestedPosition: number) {
  if (!Number.isFinite(requestedPosition) || requestedPosition < 0 || audio.seekable.length === 0) return null;

  for (let index = 0; index < audio.seekable.length; index += 1) {
    const start = audio.seekable.start(index);
    const end = audio.seekable.end(index);
    if (requestedPosition >= start && requestedPosition <= end) {
      return Math.min(requestedPosition, Math.max(start, end - 0.05));
    }
  }
  return null;
}

export async function resumeMediaElement({
  audio,
  fallbackPosition,
  refreshSource,
  isCurrent = () => true,
  metadataTimeoutMs = 8000,
  progressionTimeoutMs = 1300,
  minimumProgressSeconds = 0.1,
  onRecoveryEvent,
}: ResumeMediaElementInput): Promise<ResumeMediaElementResult> {
  const positionBeforePlay = Number.isFinite(audio.currentTime)
    ? audio.currentTime
    : Math.max(0, fallbackPosition);

  // A rejected play is handled by the caller's normal error path. Recovery is
  // reserved for WebKit's false-positive success where playback never advances.
  await audio.play();
  if (!isCurrent()) return "cancelled";
  if (await isActuallyProgressing(audio, positionBeforePlay, progressionTimeoutMs, minimumProgressSeconds)) {
    return isCurrent() ? "resumed" : "cancelled";
  }
  if (!isCurrent() || audio.ended) return "cancelled";

  const snapshot: AudioSnapshot = {
    src: audio.currentSrc || audio.src,
    currentTime: Number.isFinite(audio.currentTime) ? audio.currentTime : Math.max(0, fallbackPosition),
    playbackRate: audio.playbackRate,
    volume: audio.volume,
    muted: audio.muted,
  };

  onRecoveryEvent?.("audio_recovery_started");
  try {
    const refreshedSource = await refreshSource();
    if (!isCurrent()) return "cancelled";

    const mediaReady = waitForFreshMedia(audio, metadataTimeoutMs);
    audio.pause();
    audio.src = refreshedSource || snapshot.src;
    audio.load();
    await mediaReady;
    if (!isCurrent()) return "cancelled";

    audio.volume = snapshot.volume;
    audio.muted = snapshot.muted;
    audio.playbackRate = snapshot.playbackRate;
    const restoredPosition = seekablePosition(audio, snapshot.currentTime);
    if (restoredPosition != null) audio.currentTime = restoredPosition;

    const recoveryPosition = audio.currentTime;
    await audio.play();
    if (!isCurrent()) return "cancelled";
    const recovered = await isActuallyProgressing(
      audio,
      recoveryPosition,
      progressionTimeoutMs,
      minimumProgressSeconds,
    );
    if (!isCurrent()) return "cancelled";
    if (!recovered) {
      onRecoveryEvent?.("audio_recovery_failed", "playback-did-not-progress-after-reload");
      return "failed";
    }

    onRecoveryEvent?.("audio_recovery_succeeded");
    return "reloaded";
  } catch (error) {
    onRecoveryEvent?.(
      "audio_recovery_failed",
      error instanceof Error ? error.message : "unknown-recovery-error",
    );
    return isCurrent() ? "failed" : "cancelled";
  }
}
