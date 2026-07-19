type MediaSessionActionName =
  | "play"
  | "pause"
  | "previoustrack"
  | "nexttrack"
  | "seekbackward"
  | "seekforward"
  | "seekto";

type MediaSessionLike = {
  setActionHandler: (action: MediaSessionActionName, handler: MediaSessionActionHandler | null) => void;
  playbackState?: MediaSessionPlaybackState;
};

type NavigatorPlatformLike = {
  userAgent?: string;
  platform?: string;
  maxTouchPoints?: number;
};

type ConfigureMediaSessionActionsInput = {
  mediaSession: MediaSessionLike;
  play: () => void | Promise<void>;
  pause: () => void | Promise<void>;
  next: () => void | Promise<void>;
  previous: () => void | Promise<void>;
  seekTo: (position: number, fastSeek: boolean) => void | Promise<void>;
  enableSeekTo?: boolean;
  enableTransportHandlers?: boolean;
};

function safelySetHandler(
  mediaSession: MediaSessionLike,
  action: MediaSessionActionName,
  handler: MediaSessionActionHandler | null,
) {
  try {
    mediaSession.setActionHandler(action, handler);
  } catch {
    // Some browsers expose the Media Session API but reject unsupported actions.
  }
}

function safelyRunAction(action: () => void | Promise<void>) {
  try {
    const result = action();
    if (result && typeof result.then === "function") void result.catch(() => undefined);
  } catch {
    // Hardware and lock-screen controls must not surface player callback errors.
  }
}

export function configureMediaSessionActions({
  mediaSession,
  play,
  pause,
  next,
  previous,
  seekTo,
  enableSeekTo = true,
  enableTransportHandlers = true,
}: ConfigureMediaSessionActionsInput) {
  // Remove interval seeking before publishing track navigation. WebKit maps
  // these actions to the ±10s Now Playing commands on Apple platforms.
  safelySetHandler(mediaSession, "seekbackward", null);
  safelySetHandler(mediaSession, "seekforward", null);
  if (!enableSeekTo) safelySetHandler(mediaSession, "seekto", null);

  if (enableTransportHandlers) {
    safelySetHandler(mediaSession, "play", () => {
      safelyRunAction(play);
    });
    safelySetHandler(mediaSession, "pause", () => {
      safelyRunAction(pause);
    });
  } else {
    // On iOS, custom play/pause handlers race WebKit's own audio-element
    // transport and can leave the timeline running while the output is silent.
    safelySetHandler(mediaSession, "play", null);
    safelySetHandler(mediaSession, "pause", null);
  }

  if (enableSeekTo) {
    safelySetHandler(mediaSession, "seekto", (details) => {
      if (typeof details.seekTime !== "number" || !Number.isFinite(details.seekTime)) return;
      safelyRunAction(() => seekTo(Math.max(0, details.seekTime as number), details.fastSeek === true));
    });
  }

  // Register these last so Cocoa's final supported-command update advertises
  // playlist navigation rather than interval seeking.
  safelySetHandler(mediaSession, "previoustrack", () => safelyRunAction(previous));
  safelySetHandler(mediaSession, "nexttrack", () => safelyRunAction(next));
}

export function prefersTrackNavigationOnly({
  userAgent = "",
  platform = "",
  maxTouchPoints = 0,
}: NavigatorPlatformLike) {
  if (/iPhone|iPad|iPod/i.test(userAgent)) return true;

  // iPadOS can request a desktop user agent and report itself as MacIntel.
  return /Mac/i.test(platform || userAgent) && maxTouchPoints > 1;
}

export function clearMediaSessionActions(mediaSession: MediaSessionLike) {
  for (const action of ["play", "pause", "nexttrack", "previoustrack", "seekbackward", "seekforward", "seekto"] as const) {
    safelySetHandler(mediaSession, action, null);
  }
}
