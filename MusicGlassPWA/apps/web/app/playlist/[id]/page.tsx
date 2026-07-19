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

export default function PlaylistPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;
  const playTrack = usePlaybackStore((state) => state.playTrack);

  const { data, isLoading, error } = useQuery({
    queryKey: ["playlist", id],
    queryFn: async () => parsePlaylist(await fetchPlaylist(id)),
  });

  const playableTracks = useMemo(() => (data?.tracks ?? [])
    .filter((item) => item.type === "track" || item.type === "video")
    .map((item) => normalizeTrack({
      id: item.id,
      title: item.title,
      artist: item.artist || data?.artist,
      album: data?.title,
      artwork: item.artwork || data?.artwork,
      duration: item.duration || 0,
    })), [data]);

  if (isLoading) {
    return <DetailSkeleton />;
  }

  if (error || !data) {
    return <div className="page detail-loading detail-error">Impossible de charger la playlist.</div>;
  }

  const playAll = () => {
    if (playableTracks[0]) playTrack(playableTracks[0], playableTracks);
  };

  return (
    <div className="page detail-page">
      <div className="detail-glow" style={{ backgroundImage: data.artwork ? `url(${data.artwork})` : undefined }} />
      <div className="detail-toolbar">
        <Button onClick={() => router.back()} className="detail-back" variant="soft" size="sm">
          <ArrowLeft size={18} />
          Retour
        </Button>
      </div>

      <header className="detail-header">
        {data.artwork ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img className="detail-cover" src={data.artwork} alt={`Pochette de ${data.title}`} onError={handleArtworkError} />
        ) : (
          <div className="detail-cover artwork-fallback" role="img" aria-label={`Pochette de ${data.title}`} />
        )}
        <div className="detail-copy">
          <h1>{data.title}</h1>
          <div className="detail-meta">
            <Badge variant="soft" size="sm">Playlist</Badge>
            {data.subtitle && <span>{data.subtitle}</span>}
            <span>{playableTracks.length} {playableTracks.length > 1 ? "titres" : "titre"}</span>
          </div>
        </div>
        <Button className="detail-play" size="lg" onClick={playAll} disabled={!playableTracks.length}>
          <Play data-icon="start" fill="currentColor" size={20} />
          Tout lire
        </Button>
      </header>

      <section className="detail-track-list" aria-label="Titres de la playlist">
        {data.tracks.map((track, index) => {
          const currentTrack = playableTracks.find((item) => item.id === track.id);
          const displayTrack = normalizeTrack({
            id: track.id,
            title: track.title,
            artist: track.artist || data.artist,
            album: data.title,
            artwork: track.artwork || data.artwork,
            duration: track.duration || 0,
          });
          return (
            <TrackRow
              key={`${track.id}-${index}`}
              track={displayTrack}
              index={index}
              onPlay={() => currentTrack && playTrack(currentTrack, playableTracks)}
            />
          );
        })}
      </section>
    </div>
  );
}

function DetailSkeleton() {
  return (
    <div className="page detail-page">
      <div className="detail-skeleton-header">
        <Skeleton className="skeleton-cover" />
        <Skeleton className="skeleton-line skeleton-title" />
        <Skeleton className="skeleton-line skeleton-muted" />
      </div>
      <div className="detail-track-list">
        {Array.from({ length: 7 }).map((_, index) => (
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
