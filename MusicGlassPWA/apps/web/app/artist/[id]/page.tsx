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
      if (!artistName || artist.tracks.length === 0) throw new Error("Artist metadata unavailable");

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

  if (isLoading) return <ArtistSkeleton />;
  if (error || !data) {
    return (
      <main className={`${styles.artistPage} ${styles.centered}`}>
        <BackButton onBack={() => router.back()} />
        <p>Impossible de charger l’artiste.</p>
      </main>
    );
  }

  const playAll = () => {
    if (primaryTracks[0]) playTrack(primaryTracks[0], primaryTracks);
  };

  return (
    <main className={styles.artistPage}>
      <BackButton onBack={() => router.back()} />
      <header className={styles.artistHero}>
        {data.image ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={data.image} alt={`Portrait de ${data.name}`} onError={handleArtworkError} />
        ) : (
          <div className={styles.artworkFallback} role="img" aria-label={`Portrait de ${data.name}`} />
        )}
        <div className={styles.artistScrim} />
        <div className={styles.artistIdentity}>
          <span>
            <span aria-hidden="true">✓</span>
            Artiste
          </span>
          <h1>{data.name}</h1>
          <p>
            {primaryTracks.length} {primaryTracks.length > 1 ? "titres disponibles" : "titre disponible"}
          </p>
        </div>
      </header>

      <div className={styles.artistActions}>
        <button className={styles.primaryPlay} type="button" onClick={playAll} disabled={!primaryTracks.length}>
          <Play size={17} fill="currentColor" />
          Lecture
        </button>
      </div>

      {primaryTracks.length > 0 && (
        <section className={styles.artistSection}>
          <div className={styles.sectionHeading}>
            <span className={styles.kicker}>Discographie</span>
            <h2>Titres populaires</h2>
          </div>
          <div className={styles.trackList}>
            {primaryTracks.slice(0, 5).map((track, index) => (
              <TrackRow
                key={`${track.id}-${index}`}
                track={track}
                index={index}
                variant="artist"
                onPlay={() => playTrack(track, primaryTracks)}
              />
            ))}
          </div>
        </section>
      )}
    </main>
  );
}

function BackButton({ onBack }: { onBack: () => void }) {
  return (
    <button type="button" className={styles.backButton} onClick={onBack} aria-label="Retour">
      <ArrowLeft size={19} />
    </button>
  );
}

function ArtistSkeleton() {
  return (
    <main className={styles.artistPage}>
      <Skeleton className={styles.artistHeroSkeleton} />
      <div className={styles.artistActions}>
        <Skeleton className={styles.playSkeleton} />
      </div>
      <div className={styles.trackList}>
        <Skeleton className={styles.titleSkeleton} />
        {Array.from({ length: 5 }).map((_, index) => (
          <Skeleton className={styles.rowSkeleton} key={index} />
        ))}
      </div>
    </main>
  );
}
