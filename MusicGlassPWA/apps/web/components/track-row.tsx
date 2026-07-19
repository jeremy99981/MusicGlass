"use client";

import { Button, Thumbnail } from "@appica/ui-react";
import { MoreHorizontal, Play } from "lucide-react";
import type { Track } from "@/lib/catalog";
import { handleArtworkError } from "@/lib/artwork";

export function TrackRow({ track, index, onPlay }: { track: Track; index: number; onPlay: () => void }) {
  return (
    <article className="track-row relative">
      <Button
        type="button"
        variant="ghost"
        className="absolute inset-0 z-0 h-auto w-auto rounded-[inherit] p-0"
        aria-label={`Lire ${track.title}`}
        onClick={onPlay}
      />
      <div className="track-art pointer-events-none z-1">
        {track.artwork && (
          <Thumbnail
            src={track.artwork}
            alt=""
            className="size-full!"
            // Thumbnail's native image slot keeps the catalog retry handler intact.
            render={
              // eslint-disable-next-line @next/next/no-img-element
              <img alt="" loading="lazy" onError={handleArtworkError} />
            }
          />
        )}
        <span><Play size={18} fill="currentColor" /></span>
      </div>
      <div className="track-meta pointer-events-none z-1">
        <strong>{track.title}</strong>
        <span>{track.artist}</span>
      </div>
      <span className="track-index pointer-events-none z-1">{String(index + 1).padStart(2, "0")}</span>
      <Button type="button" variant="ghost" size="icon-sm" className="icon-button z-2" aria-label="Plus d’options">
        <MoreHorizontal />
      </Button>
    </article>
  );
}
