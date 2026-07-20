"use client";

import { Play } from "lucide-react";
import type { Track } from "@/lib/catalog";
import { handleArtworkError } from "@/lib/artwork";
import styles from "@/components/details/nocturne-details.module.css";

type TrackRowProps = {
  track: Track;
  index: number;
  onPlay: () => void;
  variant?: "artist" | "playlist";
};

function formatDuration(duration: number) {
  if (!Number.isFinite(duration) || duration <= 0) return "";
  const minutes = Math.floor(duration / 60);
  const seconds = Math.floor(duration % 60);
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function TrackRow({ track, index, onPlay, variant = "playlist" }: TrackRowProps) {
  return (
    <article className={`${styles.trackRow} ${styles[`${variant}TrackRow`]}`}>
      <button type="button" className={styles.trackButton} aria-label={`Lire ${track.title}`} onClick={onPlay}>
        <span className={styles.trackIndex}>{index + 1}</span>
        <span className={styles.trackArtwork}>
          {track.artwork ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={track.artwork} alt="" loading="lazy" onError={handleArtworkError} />
          ) : (
            <span className={styles.artworkFallback} aria-hidden="true" />
          )}
          <span className={styles.trackPlay}><Play size={15} fill="currentColor" /></span>
        </span>
        <span className={styles.trackMeta}>
          <strong>{track.title}</strong>
          <small>{track.artist || (variant === "artist" ? "Titre populaire" : "Artiste")}</small>
        </span>
        {track.duration > 0 && <span className={styles.trackDuration}>{formatDuration(track.duration)}</span>}
      </button>
    </article>
  );
}
