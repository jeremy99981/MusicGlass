"use client";

import { useQuery } from "@tanstack/react-query";
import { Badge } from "@appica/ui-react/badge";
import { Button } from "@appica/ui-react/button";
import { Skeleton } from "@appica/ui-react/skeleton";
import { ArrowLeft, Play } from "lucide-react";
import { useParams, useRouter } from "next/navigation";
import { useMemo } from "react";
import { TrackRow } from "@/components/track-row";
import { fetchPlaylist } from "@/lib/api";
import { handleArtworkError } from "@/lib/artwork";
import { normalizeTrack } from "@/lib/catalog";
import { parsePlaylist } from "@/lib/youtube";
import { usePlaybackStore } from "@/store/playback-store";

export default function ArtistPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;
  const playTrack = usePlaybackStore((state) => state.playTrack);

  const { data, isLoading, error } = useQuery({
    queryKey: ["artist", id],
    queryFn: async () => {
      const artist = parsePlaylist(await fetchPlaylist(id));
      const artistName = artist.title === "Playlist" ? artist.artist : artist.title;
      if (!artistName || artist.tracks.length === 0) {
        throw new Error("Artist metadata unavailable");
      }

      return {
        name: artistName,
        image: artist.artwork,
        tracks: artist.tracks.map((item) => normalizeTrack({
          id: item.id,
          title: item.title,
          artist: item.artist || artistName,
          album: "",
          artwork: item.artwork || artist.artwork,
          duration: item.duration || 0,
        })),
      };
    },
  });

  const primaryTracks = useMemo(() => data?.tracks ?? [], [data?.tracks]);

  if (isLoading) {
    return (
      <div className="page artist-page artist-loading-page">
        <div className="artist-hero-skeleton">
          <Skeleton className="skeleton-pill skeleton-short" />
          <Skeleton className="skeleton-line skeleton-title" />
          <Skeleton className="skeleton-line" />
        </div>
        <div className="detail-track-list">
          {Array.from({ length: 6 }).map((_, index) => (
            <div className="skeleton-row" key={index}>
              <Skeleton className="skeleton-art" />
              <div>
                <Skeleton className="skeleton-line" />
                <Skeleton className="skeleton-line skeleton-muted" />
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  if (error || !data) {
    return (
      <div className="page detail-loading detail-error">
        <Button onClick={() => router.back()} className="detail-back-inline" variant="ghost">
          <ArrowLeft size={18} /> Retour
        </Button>
        Impossible de charger l’artiste.
      </div>
    );
  }

  const playAll = () => {
    if (primaryTracks[0]) playTrack(primaryTracks[0], primaryTracks);
  };

  return (
    <div className="page artist-page">
      <div className="artist-glow" style={{ backgroundImage: data.image ? `url(${data.image})` : undefined }} />
      <div className="detail-toolbar">
        <Button onClick={() => router.back()} className="detail-back artist-back" variant="soft" size="sm">
          <ArrowLeft size={18} />
          Retour
        </Button>
      </div>

      <header className="artist-hero">
        {data.image ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={data.image} alt={`Portrait de ${data.name}`} className="artist-portrait" onError={handleArtworkError} />
        ) : (
          <div className="artist-portrait artwork-fallback" role="img" aria-label={`Portrait de ${data.name}`} />
        )}
        <div className="artist-copy">
          <h1>{data.name}</h1>
          <div className="detail-meta">
            <Badge variant="soft" size="sm">Artiste</Badge>
            <span>{primaryTracks.length ? `${primaryTracks.length} titres disponibles` : "Discographie et recommandations"}</span>
          </div>
        </div>
        <Button className="artist-play" size="lg" onClick={playAll} disabled={!primaryTracks.length}>
          <Play data-icon="start" size={20} fill="currentColor" />
          Tout lire
        </Button>
      </header>

      {primaryTracks.length > 0 && (
        <section className="artist-section">
          <div className="section-header">
            <h2>Titres populaires</h2>
          </div>
          <div className="detail-track-list artist-track-list">
            {primaryTracks.slice(0, 8).map((track, index) => (
              <TrackRow
                key={`${track.id}-${index}`}
                track={track}
                index={index}
                onPlay={() => playTrack(track, primaryTracks)}
              />
            ))}
          </div>
        </section>
      )}
    </div>
  );
}
