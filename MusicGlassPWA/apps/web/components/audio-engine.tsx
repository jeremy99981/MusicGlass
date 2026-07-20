"use client";

import { useCallback, useEffect, useRef } from "react";
import { usePlaybackStore } from "@/store/playback-store";
import { fetchRadio, getAudioStreamUrl, getMediaArtworkUrl, invalidateAudioStream, resolveAudioStream } from "@/lib/api";
import { DEFAULT_ACCENT, hasReliableTrackMetadata, normalizeTrack, uniqueTracks, type Track } from "@/lib/catalog";
import { resumeMediaElement } from "@/lib/audio-resume";
import { activatePlaybackAudioSession } from "@/lib/audio-session";
import { highResolutionArtwork } from "@/lib/youtube";
import {
  clearMediaSessionActions,
  configureMediaSessionActions,
} from "@/lib/media-session";
import { useSharedSessionStore } from "@/store/shared-session-store";

function radioItemToTrack(item: unknown): Track | null {
  if (!item || typeof item !== "object") return null;
  const value = item as Partial<Track> & { id?: unknown; title?: unknown; artist?: unknown; artwork?: unknown };
  if (typeof value.id !== "string") return null;
  const track = normalizeTrack({
    id: value.id,
    title: typeof value.title === "string" ? value.title : undefined,
    artist: typeof value.artist === "string" ? value.artist : undefined,
    album: typeof value.album === "string" ? value.album : "",
    artwork: typeof value.artwork === "string" ? value.artwork : "",
    duration: typeof value.duration === "number" ? value.duration : 0,
    accent: typeof value.accent === "string" ? value.accent : DEFAULT_ACCENT,
  });
  return hasReliableTrackMetadata(track) ? track : null;
}

const RECOMMENDATION_TARGET = 28;
const RECOMMENDATION_FETCH_LIMIT = 4;
const RECOMMENDATION_RETRY_LIMIT = 3;
type ResumePlaybackSource = "ui" | "media-session" | "internal" | "visibility";

export function AudioEngine() {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const trackIdRef = useRef<string | null>(null);
  const loadedTrackIdRef = useRef<string | null>(null);
  const warmedTracksRef = useRef<Set<string>>(new Set());
  const queueRequestRef = useRef<string | null>(null);
  const suppressInternalPauseRef = useRef(false);
  const playAttemptRef = useRef(0);
  const resumeInFlightRef = useRef(false);
  const recoveryInProgressRef = useRef(false);
  const recoveryAttemptedForCurrentPlayRef = useRef(false);
  const nativeDesiredPlayingRef = useRef(false);
  const advancedSourceRef = useRef<string | null>(null);
  const advanceEventLockedRef = useRef(false);
  const authoritativeDurationRef = useRef<{ trackId: string; seconds: number } | null>(null);
  const retriedTrackRef = useRef<string | null>(null);
  
  const current = usePlaybackStore((state) => state.current);
  const queue = usePlaybackStore((state) => state.queue);
  const currentIndex = usePlaybackStore((state) => state.currentIndex);
  const isPlaying = usePlaybackStore((state) => state.isPlaying);
  const volume = usePlaybackStore((state) => state.volume);
  const requestedPosition = usePlaybackStore((state) => state.requestedPosition);
  const sessionStatus = useSharedSessionStore((state) => state.status);
  const isSessionHost = useSharedSessionStore((state) => state.isHost);
  const canManageQueue = sessionStatus !== "connected" || isSessionHost;
  
  const setPlaying = usePlaybackStore((state) => state.setPlaying);
  const setPosition = usePlaybackStore((state) => state.setPosition);
  const setDuration = usePlaybackStore((state) => state.setDuration);
  const setStatus = usePlaybackStore((state) => state.setStatus);
  const appendToQueue = usePlaybackStore((state) => state.appendToQueue);
  const setQueueLoading = usePlaybackStore((state) => state.setQueueLoading);
  const setQueueError = usePlaybackStore((state) => state.setQueueError);
  const clearSeek = usePlaybackStore((state) => state.clearSeek);

  const publishCurrentMediaMetadata = useCallback(() => {
    if (!("mediaSession" in navigator)) return;
    const track = usePlaybackStore.getState().current;
    if (!track) return;
    const artwork = highResolutionArtwork(track.artwork);
    navigator.mediaSession.metadata = new MediaMetadata({
      title: track.title,
      artist: track.artist,
      album: track.album,
      artwork: artwork
        ? [{ src: getMediaArtworkUrl(artwork), sizes: "1200x1200" }]
        : [],
    });
  }, []);

  const resumePlayback = useCallback(async ({ source }: { source: ResumePlaybackSource }) => {
    nativeDesiredPlayingRef.current = true;
    if (recoveryInProgressRef.current || resumeInFlightRef.current) return;

    const track = usePlaybackStore.getState().current;
    const existingAudio = audioRef.current;
    if (!existingAudio || !track) return;

    resumeInFlightRef.current = true;
    recoveryAttemptedForCurrentPlayRef.current = false;
    const expectedTrackId = track.id;
    const attempt = ++playAttemptRef.current;
    const fallbackPosition = Number.isFinite(existingAudio.currentTime) && existingAudio.currentTime > 0
      ? existingAudio.currentTime
      : usePlaybackStore.getState().position;
    const activeSource = track.audioUrl || existingAudio.currentSrc || existingAudio.src || getAudioStreamUrl(track.id);
    const refreshedSource = new URL(activeSource, window.location.origin);
    refreshedSource.searchParams.delete("retry");
    refreshedSource.searchParams.set("resume", Date.now().toString());
    setStatus("loading");

    try {
      await activatePlaybackAudioSession(existingAudio, volume);

      // A backgrounded WKWebView can leave the AVAudioSession route dead
      // while the <audio> element still looks alive to JS (currentTime
      // keeps advancing, no error/ended fires) — simply calling play()
      // again is a no-op for WebKit in that state. A real pause()->play()
      // transition is what actually re-engages the hardware route (this
      // matches manually tapping pause then play, which does restore
      // sound), so force that cycle for every resume that isn't a fresh
      // track load.
      if (source !== "internal") {
        suppressInternalPauseRef.current = true;
        existingAudio.pause();
      }

      const result = await resumeMediaElement({
        audio: existingAudio,
        fallbackPosition,
        forceRecovery: source === "visibility",
        isCurrent: () => (
          playAttemptRef.current === attempt
          && nativeDesiredPlayingRef.current
          && usePlaybackStore.getState().current?.id === expectedTrackId
        ),
        refreshSource: () => {
          if (recoveryAttemptedForCurrentPlayRef.current) {
            throw new Error("Recovery already attempted for this play action.");
          }
          recoveryAttemptedForCurrentPlayRef.current = true;
          suppressInternalPauseRef.current = true;
          return refreshedSource.toString();
        },
        onRecoveryEvent: (event, reason) => {
          recoveryInProgressRef.current = event === "audio_recovery_started";
          if (event !== "audio_recovery_started") suppressInternalPauseRef.current = false;
          window.dispatchEvent(new CustomEvent("musicglass:audio-recovery", {
            detail: { event, source, trackId: expectedTrackId, reason },
          }));
        },
      });

      if (result === "cancelled" || !nativeDesiredPlayingRef.current) return;
      if (result === "failed") {
        setPlaying(false);
        setStatus("error", "La session audio iOS ne répond plus. Relancez la lecture manuellement.");
        if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "paused";
        return;
      }
      loadedTrackIdRef.current = expectedTrackId;
      setPlaying(true);
      setStatus("playing");
      publishCurrentMediaMetadata();
      if ("mediaSession" in navigator) {
        navigator.mediaSession.playbackState = "playing";
        // WebKit can process the inactive element's earlier pause after play()
        // resolves. Reassert the confirmed state once that event queue drains.
        window.setTimeout(() => {
          if (audioRef.current === existingAudio && usePlaybackStore.getState().isPlaying) {
            navigator.mediaSession.playbackState = "playing";
          }
        }, 0);
      }
    } catch (error) {
      if (usePlaybackStore.getState().current?.id !== expectedTrackId) return;
      console.error("Audio play failed:", error);
      setPlaying(false);
      setStatus("error", "Lecture impossible. Touchez Lecture pour réessayer.");
    } finally {
      // Only clear the shared flags if a newer resume/track change hasn't already
      // superseded this attempt, otherwise we would wipe the successor's state.
      if (playAttemptRef.current === attempt) {
        suppressInternalPauseRef.current = false;
        recoveryInProgressRef.current = false;
        resumeInFlightRef.current = false;
      }
    }
  }, [publishCurrentMediaMetadata, setPlaying, setStatus, volume]);

  const transitionFromRemoteControl = useCallback((direction: "next" | "previous") => {
    const audio = audioRef.current;
    const state = usePlaybackStore.getState();
    if (!audio || !state.current || !state.queue.length) return;

    if (direction === "next") state.next();
    else state.previous();

    const selected = usePlaybackStore.getState().current;
    if (!selected) return;

    nativeDesiredPlayingRef.current = true;
    suppressInternalPauseRef.current = true;
    const source = selected.audioUrl || getAudioStreamUrl(selected.id);
    const absoluteSource = new URL(source, window.location.origin).href;

    if (audio.src !== absoluteSource) {
      audio.src = source;
      audio.load();
    }
    audio.currentTime = 0;
    loadedTrackIdRef.current = selected.id;
    trackIdRef.current = selected.id;
    void activatePlaybackAudioSession(audio, usePlaybackStore.getState().volume);
    setStatus("loading");
    publishCurrentMediaMetadata();
    suppressInternalPauseRef.current = false;
    void resumePlayback({ source: "media-session" });
  }, [publishCurrentMediaMetadata, resumePlayback, setStatus]);

  const configureRemoteControls = useCallback(() => {
    if (!("mediaSession" in navigator)) return;

    configureMediaSessionActions({
      mediaSession: navigator.mediaSession,
      enableSeekTo: true,
      enableTransportHandlers: true,
      play: () => resumePlayback({ source: "media-session" }),
      pause: () => {
        nativeDesiredPlayingRef.current = false;
        playAttemptRef.current += 1;
        usePlaybackStore.getState().setPlaying(false);
        audioRef.current?.pause();
        if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "paused";
      },
      next: () => transitionFromRemoteControl("next"),
      previous: () => transitionFromRemoteControl("previous"),
      seekTo: (position) => {
        if (audioRef.current) audioRef.current.currentTime = position;
      },
    });
  }, [resumePlayback, transitionFromRemoteControl]);

  const advanceOnce = () => {
    const audio = audioRef.current;
    const trackId = usePlaybackStore.getState().current?.id;
    if (!audio || !trackId || loadedTrackIdRef.current !== trackId || advanceEventLockedRef.current) return;
    const sourceKey = `${trackId}|${audio.currentSrc}`;
    if (advancedSourceRef.current === sourceKey) return;
    advanceEventLockedRef.current = true;
    advancedSourceRef.current = sourceKey;
    transitionFromRemoteControl("next");
    window.setTimeout(() => {
      advanceEventLockedRef.current = false;
    }, 500);
  };

  const updatePositionState = () => {
    const audio = audioRef.current;
    if (!audio) return;
    if ("mediaSession" in navigator && "setPositionState" in navigator.mediaSession) {
      try {
        const state = usePlaybackStore.getState();
        const duration = state.duration > 0 ? state.duration : Number.isFinite(audio.duration) ? audio.duration : 0;
        if (duration && Number.isFinite(duration) && !isNaN(audio.currentTime)) {
          navigator.mediaSession.setPositionState({
            duration: duration,
            playbackRate: audio.playbackRate || 1.0,
            position: Math.min(audio.currentTime || 0, duration),
          });
        }
      } catch (e) {
        console.error("Error setting mediaSession position state:", e);
      }
    }
  };

  const onTimeUpdate = () => {
    if (audioRef.current) {
      setPosition(audioRef.current.currentTime || 0);
      const authoritative = authoritativeDurationRef.current;
      const shouldForceEnd = Boolean(authoritative
        && authoritative.trackId === usePlaybackStore.getState().current?.id
        && authoritative.seconds > 0
        && audioRef.current.currentTime >= authoritative.seconds - 0.12
        && (!Number.isFinite(audioRef.current.duration) || audioRef.current.duration > authoritative.seconds + 1));
      if (shouldForceEnd && usePlaybackStore.getState().isPlaying) {
        advanceOnce();
        return;
      }
      updatePositionState();
    }
  };

  const onDurationChange = () => {
    if (audioRef.current) {
      const currentTrack = usePlaybackStore.getState().current;
      const authoritative = authoritativeDurationRef.current;
      const mediaDuration = authoritative && authoritative.trackId === currentTrack?.id && authoritative.seconds > 0
        ? authoritative.seconds
        : Number.isFinite(audioRef.current.duration) && audioRef.current.duration > 0
          ? audioRef.current.duration
          : currentTrack?.duration || 0;
      setDuration(mediaDuration);
      updatePositionState();
    }
  };

  const onEnded = () => advanceOnce();

  const onPause = () => {
    if (suppressInternalPauseRef.current) return;
    nativeDesiredPlayingRef.current = false;
    setPlaying(false);
    setStatus("paused");
    if ("mediaSession" in navigator) {
      navigator.mediaSession.playbackState = "paused";
    }
  };

  const onPlay = () => {
    nativeDesiredPlayingRef.current = true;
    setPlaying(true);
    setStatus("loading");
    configureRemoteControls();
    retriedTrackRef.current = null;
  };

  const onPlaying = () => {
    nativeDesiredPlayingRef.current = true;
    setPlaying(true);
    setStatus("playing");
    publishCurrentMediaMetadata();
    if ("mediaSession" in navigator) {
      navigator.mediaSession.playbackState = "playing";
    }
  };

  const onWaiting = () => setStatus("buffering");
  const onCanPlay = () => {
    if (usePlaybackStore.getState().isPlaying) setStatus("playing");
  };
  const onLoadedMetadata = () => {
    onDurationChange();
    configureRemoteControls();
  };
  const onError = () => {
    const audio = audioRef.current;
    const failedTrack = usePlaybackStore.getState().current;
    if (!audio || !failedTrack) return;

    if (retriedTrackRef.current !== failedTrack.id) {
      retriedTrackRef.current = failedTrack.id;
      invalidateAudioStream(failedTrack);
      setStatus("loading");
      void resolveAudioStream(failedTrack)
        .then((resolved) => {
          if (usePlaybackStore.getState().current?.id !== failedTrack.id) return;
          const freshSource = new URL(resolved.stream_url || getAudioStreamUrl(failedTrack.id), window.location.origin);
          freshSource.searchParams.set("retry", Date.now().toString());
          suppressInternalPauseRef.current = true;
          audio.src = freshSource.toString();
          audio.load();
          void activatePlaybackAudioSession(audio, usePlaybackStore.getState().volume);
          suppressInternalPauseRef.current = false;
          return resumePlayback({ source: "internal" });
        })
        .catch(() => {
          suppressInternalPauseRef.current = false;
          if (usePlaybackStore.getState().current?.id === failedTrack.id) advanceOnce();
        });
      return;
    }

    setStatus("error", "Source indisponible, passage au morceau suivant.");
    window.setTimeout(advanceOnce, 250);
  };

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !current) return;
    const trackChanged = trackIdRef.current !== current.id;
    const desiredPlaying = usePlaybackStore.getState().isPlaying;
    let cancelled = false;

    setStatus(desiredPlaying ? "loading" : "paused");
    if (trackChanged) {
      retriedTrackRef.current = null;
      authoritativeDurationRef.current = null;
      // A newly selected track must supersede any resume still in flight for the
      // previous one (e.g. the visibility/pageshow resume fired when the app
      // returns to the foreground). Without this, that in-flight resume keeps
      // resumeInFlightRef truthy, so this track's own resumePlayback() would
      // early-return and the old audio would keep playing under the new artwork.
      playAttemptRef.current += 1;
      resumeInFlightRef.current = false;
      recoveryInProgressRef.current = false;
      advancedSourceRef.current = null;
    }

    const prepareAndMaybePlay = async () => {
      try {
        // Remote controls already switched and started this exact source in
        // their synchronous user-action callback. Do not replace it after an
        // asynchronous resolver round-trip, which breaks iOS audio focus.
        if (loadedTrackIdRef.current === current.id && audio.currentSrc) {
          authoritativeDurationRef.current = current.duration > 0
            ? { trackId: current.id, seconds: current.duration }
            : null;
          if (current.duration > 0) setDuration(current.duration);
          suppressInternalPauseRef.current = false;
          return;
        }

        const resolved = current.audioUrl ? { stream_url: current.audioUrl } : await resolveAudioStream(current);
        if (cancelled) return;
        const resolvedDuration = Number("duration_seconds" in resolved ? resolved.duration_seconds : 0);
        if (Number.isFinite(resolvedDuration) && resolvedDuration > 0) {
          authoritativeDurationRef.current = { trackId: current.id, seconds: resolvedDuration };
          setDuration(resolvedDuration);
        }
        const source = resolved.stream_url || getAudioStreamUrl(current.id);
        const absoluteSource = new URL(source, window.location.origin).href;

        loadedTrackIdRef.current = current.id;
        if (audio.src !== absoluteSource) {
          suppressInternalPauseRef.current = true;
          audio.src = source;
          audio.load();
        }

        if (trackChanged) {
          audio.currentTime = 0;
        }

        if (desiredPlaying) {
          void activatePlaybackAudioSession(audio, usePlaybackStore.getState().volume);
          suppressInternalPauseRef.current = false;
          void resumePlayback({ source: "internal" });
        } else {
          queueMicrotask(() => {
            if (!cancelled) suppressInternalPauseRef.current = false;
          });
        }
      } catch {
        if (!cancelled) {
          suppressInternalPauseRef.current = false;
          audio.removeAttribute("src");
          audio.load();
          setPlaying(false);
          setPosition(0);
          setDuration(0);
          setStatus("error", "Lecture bloquée par YouTube: connectez YouTube Music côté serveur pour fournir les cookies nécessaires.");
        }
      }
    };

    prepareAndMaybePlay();

    trackIdRef.current = current.id;
    
    if ("mediaSession" in navigator) {
      publishCurrentMediaMetadata();
      navigator.mediaSession.playbackState = usePlaybackStore.getState().isPlaying ? "playing" : "paused";
      configureRemoteControls();
      updatePositionState();
    }
    return () => {
      cancelled = true;
    };
  }, [configureRemoteControls, current, publishCurrentMediaMetadata, resumePlayback, setDuration, setPlaying, setPosition, setStatus]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || !current) return;
    if (isPlaying) {
      if (audio.paused && audio.currentSrc) {
        void activatePlaybackAudioSession(audio, volume);
        void resumePlayback({ source: "ui" });
      }
    } else {
      if (!audio.paused) {
        audio.pause();
      }
    }
  }, [current, isPlaying, resumePlayback, volume]);

  useEffect(() => {
    const playback = usePlaybackStore.getState();
    const remaining = playback.queue.length - playback.currentIndex - 1;
    if (
      !current ||
      remaining >= RECOMMENDATION_TARGET ||
      queueRequestRef.current === current.id ||
      !canManageQueue
    ) return;

    queueRequestRef.current = current.id;
    setQueueLoading(true);
    let cancelled = false;
    const controller = new AbortController();

    const fillContinuousQueue = async () => {
      const knownIds = new Set(usePlaybackStore.getState().queue.map((track) => track.id));
      let seed = current;
      let added = 0;

      for (let attempt = 0; attempt < RECOMMENDATION_FETCH_LIMIT && remaining + added < RECOMMENDATION_TARGET; attempt += 1) {
        let radio: Awaited<ReturnType<typeof fetchRadio>> | null = null;
        for (let retry = 0; retry < RECOMMENDATION_RETRY_LIMIT && !radio; retry += 1) {
          try {
            radio = await fetchRadio(seed, controller.signal);
          } catch (error) {
            if (controller.signal.aborted) throw error;
            if (retry === RECOMMENDATION_RETRY_LIMIT - 1) throw error;
            await new Promise((resolve) => window.setTimeout(resolve, 350 * (retry + 1)));
          }
        }
        if (!radio) break;
        if (cancelled) return;
        const candidates = uniqueTracks(
          radio.tracks
            .map(radioItemToTrack)
            .filter((track): track is Track => Boolean(track))
            .filter((track) => !knownIds.has(track.id)),
        );
        if (!candidates.length) break;

        candidates.forEach((track) => knownIds.add(track.id));
        appendToQueue(candidates);
        added += candidates.length;
        seed = candidates[candidates.length - 1];
      }

      if (!cancelled) {
        setQueueError(added > 0 ? null : "Aucune recommandation musicale fiable disponible pour le moment.");
      }
    };

    fillContinuousQueue()
      .catch(() => {
        if (!cancelled) setQueueError("Impossible d’actualiser les recommandations musicales.");
      })
      .finally(() => {
        if (!cancelled) setQueueLoading(false);
      });

    return () => {
      cancelled = true;
      controller.abort();
      if (queueRequestRef.current === current.id) queueRequestRef.current = null;
      setQueueLoading(false);
    };
  }, [appendToQueue, canManageQueue, current, currentIndex, setQueueError, setQueueLoading]);

  useEffect(() => {
    const nextTrack = queue[currentIndex + 1];
    if (!nextTrack || nextTrack.audioUrl || warmedTracksRef.current.has(nextTrack.id)) return;

    // A second <audio> element is disruptive on iOS and can starve the active
    // stream through a remote tunnel. Resolve only the immediate next track,
    // after the current one has had time to establish its buffer.
    const timer = window.setTimeout(() => {
      warmedTracksRef.current.add(nextTrack.id);
      void resolveAudioStream(nextTrack).catch(() => warmedTracksRef.current.delete(nextTrack.id));
    }, 2500);
    return () => window.clearTimeout(timer);
  }, [current?.id, currentIndex, queue]);

  useEffect(() => {
    if (audioRef.current) audioRef.current.volume = volume;
  }, [volume]);

  useEffect(() => {
    if (requestedPosition == null || !audioRef.current) return;
    audioRef.current.currentTime = requestedPosition;
    if (requestedPosition <= 0.1) advancedSourceRef.current = null;
    clearSeek();
  }, [clearSeek, requestedPosition]);

  useEffect(() => {
    if (!("mediaSession" in navigator)) return;

    // A backgrounded WKWebView can silently kill the AVAudioSession route
    // without ever firing a `pause` event on the <audio> element, so
    // `audio.paused` cannot be trusted to decide whether playback needs to
    // be reactivated here. If the store still says we should be playing,
    // force a real resume (with forced recovery, see resumePlayback) rather
    // than only re-registering the MediaSession action handlers.
    const reactivateOnForeground = () => {
      configureRemoteControls();
      if (usePlaybackStore.getState().isPlaying) {
        void resumePlayback({ source: "visibility" });
      }
    };
    const reactivateIfVisible = () => {
      if (document.visibilityState === "visible") reactivateOnForeground();
    };

    reactivateOnForeground();
    window.addEventListener("pageshow", reactivateOnForeground);
    document.addEventListener("visibilitychange", reactivateIfVisible);

    return () => {
      window.removeEventListener("pageshow", reactivateOnForeground);
      document.removeEventListener("visibilitychange", reactivateIfVisible);
      if (!("mediaSession" in navigator)) return;
      clearMediaSessionActions(navigator.mediaSession);
    };
  }, [configureRemoteControls, resumePlayback]);

  return (
    <>
      <audio
        ref={audioRef}
        data-audio-slot="primary"
        data-audio-active="true"
        playsInline
        preload="metadata"
        onTimeUpdate={(event) => event.currentTarget === audioRef.current && onTimeUpdate()}
        onDurationChange={(event) => event.currentTarget === audioRef.current && onDurationChange()}
        onLoadedMetadata={(event) => event.currentTarget === audioRef.current && onLoadedMetadata()}
        onEnded={(event) => event.currentTarget === audioRef.current && onEnded()}
        onPause={(event) => event.currentTarget === audioRef.current && onPause()}
        onPlay={onPlay}
        onPlaying={onPlaying}
        onWaiting={(event) => event.currentTarget === audioRef.current && onWaiting()}
        onStalled={(event) => event.currentTarget === audioRef.current && onWaiting()}
        onCanPlay={(event) => event.currentTarget === audioRef.current && onCanPlay()}
        onError={(event) => event.currentTarget === audioRef.current && onError()}
        style={{
          position: "fixed",
          left: -2,
          bottom: 0,
          width: 1,
          height: 1,
          opacity: 0.01,
          pointerEvents: "none",
        }}
      />
    </>
  );
}
