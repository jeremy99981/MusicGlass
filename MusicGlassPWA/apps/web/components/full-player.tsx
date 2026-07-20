"use client";

import { motion, useReducedMotion } from "motion/react";
import { Button } from "@appica/ui-react/button";
import { Skeleton } from "@appica/ui-react/skeleton";
import { useEffect, useState, type CSSProperties } from "react";
import { addLibraryLike } from "@/lib/api";
import { DEFAULT_ACCENT } from "@/lib/catalog";
import { usePlaybackStore } from "@/store/playback-store";
import { PlayerHeader } from "./player/player-header";
import { PlayerArtwork } from "./player/player-artwork";
import { PlayerTimeline } from "./player/player-timeline";
import { PlayerControls } from "./player/player-controls";
import { ArrowRight, Disc3, Heart, ListMusic, LoaderCircle } from "lucide-react";
import { handleArtworkError } from "@/lib/artwork";
import { AuthRequiredDialog } from "./auth-required-dialog";

function UpNextArtwork({ artwork }: { artwork: string }) {
  const [isLoaded, setIsLoaded] = useState(false);

  return (
    <span className="fp-up-next-artwork">
      {!isLoaded && <Skeleton className="fp-up-next-skeleton" />}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className={isLoaded ? "fp-recommendation-artwork-loaded" : ""}
        src={artwork}
        alt=""
        onLoad={() => setIsLoaded(true)}
        onError={(event) => {
          handleArtworkError(event);
          if (event.currentTarget.style.display === "none") setIsLoaded(true);
        }}
      />
    </span>
  );
}

export function FullPlayer() {
  const state = usePlaybackStore();
  const reduceMotion = useReducedMotion();
  const [likedTrackId, setLikedTrackId] = useState<string | null>(null);
  const [authPromptOpen, setAuthPromptOpen] = useState(false);

  useEffect(() => {
    document.documentElement.classList.add("player-overlay-open");
    document.body.classList.add("player-overlay-open");

    return () => {
      document.documentElement.classList.remove("player-overlay-open");
      document.body.classList.remove("player-overlay-open");
    };
  }, []);

  const track = state.current;
  if (!track) return null;
  const liked = likedTrackId === track.id;
  const isLoading = state.status === "loading" || state.status === "buffering";
  const queuePosition = state.currentIndex >= 0 ? state.currentIndex + 1 : 1;
  const queueLength = Math.max(state.queue.length, 1);
  const upcomingCount = Math.max(0, state.queue.length - state.currentIndex - 1);
  const nextTrack = state.queue[state.currentIndex + 1];

  const likeTrack = async () => {
    setLikedTrackId(track.id);
    try {
      await addLibraryLike(track);
    } catch {
      setLikedTrackId(null);
      setAuthPromptOpen(true);
    }
  };

  return (
    <>
    <motion.section
      className="full-player"
      style={{
        "--player-artwork": `url(${track.artwork})`,
        "--player-accent": track.accent || DEFAULT_ACCENT,
      } as CSSProperties}
      role="dialog"
      aria-modal="true"
      aria-labelledby="full-player-title"
      aria-describedby="full-player-context"
      initial={reduceMotion ? false : { opacity: 0, y: 22, scale: 0.995 }}
      animate={{ opacity: 1, y: 0, scale: 1 }}
      exit={reduceMotion ? { opacity: 0 } : { opacity: 0, y: 16, scale: 0.997 }}
      transition={reduceMotion ? { duration: 0 } : { duration: 0.24, ease: [0.2, 0.8, 0.2, 1] }}
    >
      <div className="fp-ambient" aria-hidden="true" />
      <PlayerHeader eyebrow={track.album ? "ALBUM" : "EN LECTURE"} title={track.album || track.title} />

      <div className="fp-body">
        <PlayerArtwork key={track.id} track={track} />

        <section className="fp-info" aria-label="Lecture en cours">
          <header className="fp-track-row">
            <div className="fp-track-text">
              <h1 className="fp-title" id="full-player-title">{track.title}</h1>
              <p className="fp-artist">
                <span className="fp-artist-name">{track.artist}</span>
                {track.album && (
                  <>
                    <span className="fp-metadata-separator" aria-hidden="true"> · </span>
                    <span className="fp-album">{track.album}</span>
                  </>
                )}
              </p>
              {isLoading && (
                <span className="fp-loading-state" role="status" aria-live="polite">
                  <LoaderCircle className="spin" size={14} />
                  {state.status === "buffering" ? "Stabilisation du flux..." : "Connexion audio..."}
                </span>
              )}
              {state.status === "error" && state.error && (
                <span className="fp-error-state" role="alert">{state.error}</span>
              )}
            </div>
            <Button
              variant="ghost"
              className={`fp-like ${liked ? "fp-liked" : ""}`}
              aria-label={liked ? "Titre aimé" : "Aimer"}
              onClick={likeTrack}
            >
              <Heart size={22} fill={liked ? "currentColor" : "none"} />
            </Button>
          </header>

          <PlayerTimeline />
          <PlayerControls />
          <aside
            className="fp-secondary-actions"
            id="full-player-context"
            aria-label="Contexte de lecture"
          >
            <Button
              variant="ghost"
              className="fp-queue-action"
              onClick={() => state.setQueueOpen(true)}
              aria-label={`Ouvrir la file d’attente, titre ${queuePosition} sur ${queueLength}`}
              aria-controls="playback-queue"
              aria-expanded={state.queueOpen}
            >
              <ListMusic size={19} /> File d’attente
            </Button>
            <span className="fp-queue-context" title={nextTrack ? `À suivre : ${nextTrack.title}` : undefined}>
              <Disc3 size={14} aria-hidden="true" />
              {queuePosition} / {queueLength} · {upcomingCount > 0 ? `${upcomingCount} à suivre` : "fin de la file"}
            </span>
          </aside>
          {nextTrack && (
            <Button
              variant="ghost"
              className="fp-up-next"
              onClick={() => state.setQueueOpen(true)}
              aria-label={`À suivre : ${nextTrack.title}, par ${nextTrack.artist}. Ouvrir la file d’attente`}
              aria-controls="playback-queue"
              aria-expanded={state.queueOpen}
            >
              <UpNextArtwork key={nextTrack.id} artwork={nextTrack.artwork} />
              <span className="fp-up-next-copy">
                <small>À suivre</small>
                <strong>{nextTrack.title}</strong>
                <span>{nextTrack.artist}</span>
              </span>
              <ArrowRight size={20} aria-hidden="true" />
            </Button>
          )}
        </section>
      </div>
    </motion.section>
    <AuthRequiredDialog open={authPromptOpen} onOpenChange={setAuthPromptOpen} />
    </>
  );
}
