"use client";

import { Skeleton } from "@appica/ui-react/skeleton";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Play } from "lucide-react";
import { useParams, useRouter } from "next/navigation";
import { useMemo } from "react";
import styles from "@/components/details/nocturne-details.module.css";
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

  if (isLoading) return <DetailSkeleton />;
  if (error || !data) return <DetailError message="Impossible de charger la playlist." onBack={() => router.back()} />;

  const playAll = () => {
    if (playableTracks[0]) playTrack(playableTracks[0], playableTracks);
  };

  return (
    <main className={styles.detailPage}>
      <BackButton onBack={() => router.back()} />
      <DetailHeader
        kind="Playlist"
        title={data.title}
        subtitle={data.subtitle || data.artist || "MusicGlass"}
        artwork={data.artwork}
        trackCount={playableTracks.length}
        onPlay={playAll}
      />
      <section className={styles.trackList} aria-label="Titres de la playlist">
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
    </main>
  );
}

function DetailHeader({ kind, title, subtitle, artwork, trackCount, onPlay }: {
  kind: "Album" | "Playlist";
  title: string;
  subtitle?: string;
  artwork?: string;
  trackCount: number;
  onPlay: () => void;
}) {
  return (
    <header className={styles.detailHeader}>
      {artwork ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img className={styles.detailCover} src={artwork} alt={`Pochette de ${title}`} onError={handleArtworkError} />
      ) : (
        <div className={`${styles.detailCover} ${styles.artworkFallback}`} role="img" aria-label={`Pochette de ${title}`} />
      )}
      <div className={styles.detailCopy}>
        <span className={styles.kicker}>{kind}</span>
        <h1>{title}</h1>
        <p>{[subtitle, `${trackCount} ${trackCount > 1 ? "titres" : "titre"}`].filter(Boolean).join(" · ")}</p>
      </div>
      <button className={styles.primaryPlay} type="button" onClick={onPlay} disabled={!trackCount}>
        <Play size={17} fill="currentColor" />
        Lecture
      </button>
    </header>
  );
}

function BackButton({ onBack }: { onBack: () => void }) {
  return <button type="button" className={styles.backButton} onClick={onBack} aria-label="Retour"><ArrowLeft size={19} /></button>;
}

function DetailError({ message, onBack }: { message: string; onBack: () => void }) {
  return <main className={`${styles.detailPage} ${styles.centered}`}><BackButton onBack={onBack} /><p>{message}</p></main>;
}

function DetailSkeleton() {
  return (
    <main className={styles.detailPage}>
      <div className={styles.detailHeader}>
        <Skeleton className={styles.coverSkeleton} />
        <Skeleton className={styles.titleSkeleton} />
        <Skeleton className={styles.metaSkeleton} />
      </div>
      <div className={styles.trackList}>
        {Array.from({ length: 7 }).map((_, index) => (
          <Skeleton className={styles.rowSkeleton} key={index} />
        ))}
      </div>
    </main>
  );
}
