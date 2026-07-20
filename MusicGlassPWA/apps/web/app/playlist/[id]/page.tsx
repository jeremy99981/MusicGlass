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
import { takeDetailPreview } from "@/lib/detail-preview";
import { useWindowedList } from "@/lib/use-windowed-list";
import { parsePlaylist } from "@/lib/youtube";
import { usePlaybackStore } from "@/store/playback-store";

export default function PlaylistPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;
  const playTrack = usePlaybackStore((state) => state.playTrack);
  // Aperçu capturé au clic sur le raccourci: permet d'afficher le header
  // instantanément, avant même que l'appel réseau ne réponde.
  const preview = useMemo(() => takeDetailPreview(id), [id]);
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
  // Index O(1) pour retrouver la piste jouable d'une ligne (évite un find() par ligne → O(n²)).
  const playableById = useMemo(() => new Map(playableTracks.map((track) => [track.id, track])), [playableTracks]);
  // Rendu par fenêtre: seules les ~30 premières lignes sont montées immédiatement,
  // les suivantes s'ajoutent par lots. Le rendu initial ne dépend donc plus de la
  // longueur de la playlist.
  const visibleCount = useWindowedList(data?.tracks.length ?? 0, id);

  if (error && !data) return <DetailError message="Impossible de charger la playlist." onBack={() => router.back()} />;

  // Le header s'appuie sur les données chargées, sinon sur l'aperçu du raccourci.
  const headerTitle = data?.title || preview?.title || "Playlist";
  const headerSubtitle = data?.subtitle || data?.artist || preview?.subtitle || "MusicGlass";
  const headerArtwork = data?.artwork || preview?.artwork;
  const hasHeader = Boolean(data || preview);

  const playAll = () => {
    if (playableTracks[0]) playTrack(playableTracks[0], playableTracks);
  };

  return (
    <main className={styles.detailPage}>
      <BackButton onBack={() => router.back()} />
      {hasHeader ? (
        <DetailHeader
          kind="Playlist"
          title={headerTitle}
          subtitle={headerSubtitle}
          artwork={headerArtwork}
          trackCount={data ? playableTracks.length : undefined}
          loading={isLoading && !data}
          onPlay={playAll}
        />
      ) : (
        <HeaderSkeleton />
      )}
      <section className={styles.trackList} aria-label="Titres de la playlist">
        {!data ? (
          <TrackListLoading />
        ) : (
          <>
            {data.tracks.slice(0, visibleCount).map((track, index) => {
              const currentTrack = playableById.get(track.id);
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
                  appearIndex={index}
                  artworkPending={track.artworkPending}
                  onPlay={() => currentTrack && playTrack(currentTrack, playableTracks)}
                />
              );
            })}
          </>
        )}
      </section>
    </main>
  );
}

function DetailHeader({ kind, title, subtitle, artwork, trackCount, loading, onPlay }: {
  kind: "Album" | "Playlist";
  title: string;
  subtitle?: string;
  artwork?: string;
  trackCount?: number;
  loading?: boolean;
  onPlay: () => void;
}) {
  const meta = [subtitle, trackCount ? `${trackCount} ${trackCount > 1 ? "titres" : "titre"}` : loading ? "Chargement…" : ""]
    .filter(Boolean)
    .join(" · ");
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
        <p>{meta}</p>
      </div>
      <button className={styles.primaryPlay} type="button" onClick={onPlay} disabled={!trackCount}>
        <Play size={17} fill="currentColor" />
        Lecture
      </button>
    </header>
  );
}

function TrackListLoading() {
  return (
    <div className={styles.trackListLoading} role="status" aria-live="polite">
      <span className={styles.trackListSpinner} aria-hidden="true" />
      Chargement des titres…
    </div>
  );
}

function HeaderSkeleton() {
  return (
    <div className={styles.detailHeader}>
      <Skeleton className={styles.coverSkeleton} />
      <Skeleton className={styles.titleSkeleton} />
      <Skeleton className={styles.metaSkeleton} />
    </div>
  );
}

function BackButton({ onBack }: { onBack: () => void }) {
  return <button type="button" className={styles.backButton} onClick={onBack} aria-label="Retour"><ArrowLeft size={19} /></button>;
}

function DetailError({ message, onBack }: { message: string; onBack: () => void }) {
  return <main className={`${styles.detailPage} ${styles.centered}`}><BackButton onBack={onBack} /><p>{message}</p></main>;
}
