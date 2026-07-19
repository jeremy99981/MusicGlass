"use client";

import { Skeleton } from "@appica/ui-react/skeleton";
import { useState } from "react";
import { highResolutionArtwork, Track } from "@/lib/youtube";
import { handleArtworkError } from "@/lib/artwork";

export function PlayerArtwork({ track }: { track: Track }) {
  const [isLoaded, setIsLoaded] = useState(false);
  const highResArtwork = highResolutionArtwork(track.artwork);
  const isYouTubeVideoThumb = /i\.ytimg\.com\/vi\//.test(highResArtwork);

  return (
    <div className="fp-artwork-wrap" role="figure" aria-label={`Pochette de ${track.title}`}>
      <div className="fp-artwork-frame">
        {!isLoaded && <Skeleton className="fp-artwork-skeleton" />}
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          className={`fp-artwork ${isYouTubeVideoThumb ? "fp-artwork-video" : ""} ${isLoaded ? "fp-artwork-loaded" : ""}`}
          src={highResArtwork}
          alt={`Pochette de ${track.title} par ${track.artist}`}
          onLoad={() => setIsLoaded(true)}
          onError={(event) => {
            handleArtworkError(event);
            if (event.currentTarget.style.display === "none") setIsLoaded(true);
          }}
        />
      </div>
    </div>
  );
}
