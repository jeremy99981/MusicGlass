"use client";

import React, { useState, type CSSProperties } from "react";
import { Button } from "@appica/ui-react/button";
import { Heart, ListMusic, Pause, Play, SkipBack, SkipForward } from "lucide-react";
import Image from "next/image";
import { addLibraryLike } from "@/lib/api";
import { handleArtworkError } from "@/lib/artwork";
import { usePlaybackStore } from "@/store/playback-store";
import { useSharedSessionStore } from "@/store/shared-session-store";
import { AuthRequiredDialog } from "./auth-required-dialog";

function formatTime(value: number) {
  const safeValue = Number.isFinite(value) ? Math.max(0, value) : 0;
  const minutes = Math.floor(safeValue / 60);
  const seconds = Math.floor(safeValue % 60);
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function MiniPlayer() {
  const state = usePlaybackStore();
  const { code, isHost } = useSharedSessionStore();
  const [likedTrackIds, setLikedTrackIds] = useState<Set<string>>(() => new Set());
  const [authPromptOpen, setAuthPromptOpen] = useState(false);

  if (!state.current) return null;

  const track = state.current;
  const controlsLocked = Boolean(code && !isHost);
  const safePosition = state.duration > 0
    ? Math.min(Math.max(state.position, 0), state.duration)
    : 0;
  const progress = state.duration > 0 ? (safePosition / state.duration) * 100 : 0;
  const isLiked = likedTrackIds.has(track.id);
  const remainingTracks = Math.max(0, state.queue.length - state.currentIndex - 1);

  const likeTrack = async () => {
    if (isLiked) return;
    setLikedTrackIds((current) => new Set(current).add(track.id));
    try {
      await addLibraryLike(track);
    } catch {
      setLikedTrackIds((current) => {
        const next = new Set(current);
        next.delete(track.id);
        return next;
      });
      setAuthPromptOpen(true);
    }
  };

  return (
    <>
    <div
      className="mini-player mini-player-control-center"
      role="region"
      aria-label="Lecteur audio"
      style={{
        "--mini-artwork": `url(${track.artwork})`,
        "--mini-accent": track.accent || "#176bc1",
      } as CSSProperties}
    >
      <Button
        variant="ghost"
        type="button"
        className="mini-main mini-track-info"
        onClick={() => state.setPlayerOpen(true)}
        aria-label={`Ouvrir le lecteur pour ${track.title}, ${track.artist}`}
      >
        <span className="mini-artwork-wrap">
          <Image src={track.artwork} alt="" width={58} height={58} sizes="58px" unoptimized onError={handleArtworkError} />
        </span>
        <span className="mini-track-copy">
          <strong>{track.title}</strong>
          <small>{track.artist}{track.album ? ` · ${track.album}` : ""}</small>
        </span>
      </Button>

      <div className="mini-transport" aria-label="Commandes de lecture">
        <div className="mini-controls">
          <Button variant="ghost" type="button" onClick={state.previous} disabled={controlsLocked} aria-label="Précédent">
            <SkipBack size={20} fill="currentColor" aria-hidden="true" />
          </Button>
          <Button
            variant="ghost"
            type="button"
            className="play-button small"
            disabled={controlsLocked}
            onClick={() => state.setPlaying(!state.isPlaying)}
            aria-label={controlsLocked ? "Contrôles réservés à l’hôte" : state.isPlaying ? "Pause" : "Lecture"}
          >
            {state.isPlaying
              ? <Pause size={22} fill="currentColor" aria-hidden="true" />
              : <Play size={22} fill="currentColor" aria-hidden="true" />}
          </Button>
          <Button variant="ghost" type="button" onClick={state.next} disabled={controlsLocked} aria-label="Suivant">
            <SkipForward size={20} fill="currentColor" aria-hidden="true" />
          </Button>
        </div>

        <div className="mini-timeline">
          <span className="mini-time mini-time-current" aria-hidden="true">{formatTime(safePosition)}</span>
          <input
            className="mini-timeline-input"
            type="range"
            min="0"
            max={state.duration || 1}
            step="1"
            value={safePosition}
            disabled={controlsLocked || state.duration <= 0}
            onChange={(event) => state.seekTo(Number(event.currentTarget.value))}
            aria-label="Position de lecture"
            aria-valuetext={state.duration > 0
              ? `${formatTime(safePosition)} sur ${formatTime(state.duration)}`
              : "Durée inconnue"}
          />
          <span className="mini-time mini-time-duration" aria-hidden="true">
            {state.duration > 0 ? formatTime(state.duration) : "–:––"}
          </span>
        </div>
      </div>

      <div className="mini-actions">
        <Button
          variant="ghost"
          type="button"
          className={`mini-like ${isLiked ? "mini-liked" : ""}`}
          onClick={likeTrack}
          aria-label={isLiked ? "Titre aimé" : "Aimer ce titre"}
          aria-pressed={isLiked}
        >
          <Heart size={19} fill={isLiked ? "currentColor" : "none"} aria-hidden="true" />
        </Button>
        <Button
          variant="ghost"
          type="button"
          className="mini-queue-button"
          onClick={() => state.setQueueOpen(true)}
          aria-label={`Ouvrir la file d’attente, ${remainingTracks} titre${remainingTracks === 1 ? "" : "s"} à suivre`}
          aria-controls="playback-queue"
          aria-expanded={state.queueOpen}
        >
          <ListMusic size={20} aria-hidden="true" />
          <span className="mini-queue-label">File d’attente</span>
          <span className="mini-queue-count" aria-hidden="true">{remainingTracks}</span>
        </Button>
      </div>

      <span className="mini-progress" style={{ transform: `scaleX(${progress / 100})` }} aria-hidden="true" />
    </div>
    <AuthRequiredDialog open={authPromptOpen} onOpenChange={setAuthPromptOpen} />
    </>
  );
}
