"use client";

import { useEffect, useState } from "react";
import { Button } from "@appica/ui-react/button";
import { Dialog, DialogBody, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@appica/ui-react/dialog";
import { Skeleton } from "@appica/ui-react/skeleton";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, Cloud, ExternalLink, Heart, LoaderCircle, MoreHorizontal, Plus, Radio, ShieldCheck, WifiOff } from "lucide-react";
import Link from "next/link";
import { connectYouTubeProvider, createLibraryPlaylist, fetchLibrary } from "@/lib/api";
import { collections } from "@/lib/catalog";
import { CreatePlaylistSheet } from "./create-playlist-sheet";
import { SharedSessionPanel } from "./shared-session-panel";
import styles from "./library-view.module.css";

type LibraryTab = "Playlists" | "Artistes" | "Titres aimés";

const coverGradients = [
  "linear-gradient(145deg,#6960a6,#22253a)",
  "linear-gradient(145deg,#2f6e74,#171928)",
  "linear-gradient(145deg,#8a536f,#272034)",
  "linear-gradient(145deg,#6c593f,#22232f)",
];

export function LibraryView() {
  const queryClient = useQueryClient();
  const [activeTab, setActiveTab] = useState<LibraryTab>("Playlists");
  const [createOpen, setCreateOpen] = useState(false);
  const [oauthUrl, setOauthUrl] = useState("");
  const [providerNotice, setProviderNotice] = useState("");
  const library = useQuery({ queryKey: ["library"], queryFn: fetchLibrary, retry: false });

  const createPlaylist = useMutation({
    mutationFn: createLibraryPlaylist,
    onSuccess: () => {
      setCreateOpen(false);
      queryClient.invalidateQueries({ queryKey: ["library"] });
    },
  });

  const connectProvider = useMutation({
    mutationFn: connectYouTubeProvider,
    onSuccess: (result) => {
      if (result.auth_url) {
        setOauthUrl(result.auth_url);
        setProviderNotice(result.message ?? "Connexion fournisseur disponible.");
        return;
      }
      setProviderNotice(result.message ?? "");
      queryClient.invalidateQueries({ queryKey: ["library"] });
    },
    onError: (error) => setProviderNotice(error.message),
  });

  useEffect(() => {
    const handleMessage = (event: MessageEvent) => {
      if (event.data?.type !== "musicglass:youtube-oauth") return;
      setOauthUrl("");
      setProviderNotice(event.data.message ?? "Retour Google reçu.");
      queryClient.invalidateQueries({ queryKey: ["library"] });
    };
    window.addEventListener("message", handleMessage);
    return () => window.removeEventListener("message", handleMessage);
  }, [queryClient]);

  const likes = library.data?.likes ?? [];
  const playlists = library.data?.playlists ?? [];
  const provider = library.data?.provider;
  const isAuthenticated = !library.isError;
  const fallbackPlaylists = collections.concat(collections).slice(0, 6);
  const displayedPlaylists = playlists.length ? playlists : fallbackPlaylists;

  const playlistRailItems = displayedPlaylists.slice(0, 5).map((item, index) => ({
      title: "name" in item ? item.name : item.title,
      subtitle: "name" in item ? `${item.song_count ?? 0} titres` : item.subtitle,
      artwork: "",
      color: "name" in item ? coverGradients[index % coverGradients.length] : item.color,
  }));
  const likedRailItems = likes.slice(0, 5).map((like) => ({
      title: like.song.title,
      subtitle: like.song.artist,
      artwork: like.song.cover_url ?? "",
      color: coverGradients[0],
  }));
  const railItems = {
    mostPlayed: playlistRailItems,
    recent: likedRailItems.length ? likedRailItems : playlistRailItems.slice().reverse(),
  };

  const providerTitle = !isAuthenticated
    ? "Connectez MusicGlass"
    : provider?.playback_ready
      ? "Lecture publique prête"
      : provider?.oauth_connected
        ? "Compte Google lié"
        : provider?.oauth_available
          ? "Connexion privée disponible"
          : "Lecture publique sans compte";

  const openGoogleOAuth = () => {
    if (!oauthUrl) return;
    const popup = window.open(oauthUrl, "musicglass-youtube-oauth", "popup=yes,width=520,height=720");
    if (!popup) window.location.href = oauthUrl;
    else popup.focus();
  };

  return (
    <main className={styles.page}>
      <header className={styles.header}>
        <div className={styles.titleRow}>
          <h1>Bibliothèque</h1>
          <button className={styles.addButton} type="button" onClick={() => setCreateOpen(true)} aria-label="Créer une playlist">
            <Plus size={24} />
          </button>
        </div>
        <div className={styles.tabs} aria-label="Type de contenu">
          {(["Playlists", "Artistes", "Titres aimés"] as LibraryTab[]).map((tab) => (
            <button key={tab} type="button" className={activeTab === tab ? styles.activeTab : ""} aria-pressed={activeTab === tab} onClick={() => setActiveTab(tab)}>
              {tab}
            </button>
          ))}
        </div>
      </header>

      <div className={styles.content}>
        {library.isLoading ? <LibrarySkeleton /> : activeTab === "Playlists" ? (
          <>
            <MediaRail kicker="Vos habitudes" title="Les plus écoutés" items={railItems.mostPlayed} />
            <MediaRail kicker="Reprendre" title="Écoutés récemment" items={railItems.recent} />
            <section className={styles.section}>
              <SectionTitle kicker="Tout" title="Vos playlists" />
              <div className={styles.rows}>
                {displayedPlaylists.map((item, index) => {
                  const backendPlaylist = "name" in item;
                  const title = backendPlaylist ? item.name : item.title;
                  const subtitle = backendPlaylist ? `${item.song_count ?? 0} titres` : item.subtitle;
                  const row = (
                    <>
                      <Cover title={title} color={backendPlaylist ? coverGradients[index % coverGradients.length] : item.color} size="row" />
                      <span className={styles.rowCopy}><strong>{title}</strong><small>{subtitle}</small></span>
                      <MoreHorizontal size={18} aria-hidden="true" />
                    </>
                  );
                  return backendPlaylist ? <Link className={styles.row} href={`/playlist/${item.id}`} key={item.id}>{row}</Link> : <div className={styles.row} key={`${title}-${index}`}>{row}</div>;
                })}
              </div>
            </section>
          </>
        ) : activeTab === "Titres aimés" ? (
          <section className={styles.section}>
            <SectionTitle kicker="Votre collection" title="Titres aimés" />
            <div className={styles.rows}>
              {likes.map((like) => (
                <div className={styles.row} key={like.id}>
                  <Cover title={like.song.title} artwork={like.song.cover_url} size="row" />
                  <span className={styles.rowCopy}><strong>{like.song.title}</strong><small>{like.song.artist}</small></span>
                  <Heart size={17} fill="currentColor" aria-hidden="true" />
                </div>
              ))}
              {!likes.length && <EmptyState text="Vos titres aimés apparaîtront ici." />}
            </div>
          </section>
        ) : (
          <section className={styles.section}>
            <SectionTitle kicker="Votre collection" title="Artistes" />
            <EmptyState text="Les artistes de vos titres aimés apparaîtront ici." />
          </section>
        )}

        {library.isError && (
          <div className={styles.authNotice}><WifiOff size={18} /><span>Connectez-vous pour synchroniser cette bibliothèque.</span><Link href="/login">Connexion</Link></div>
        )}

        <details className={styles.services}>
          <summary>Services connectés</summary>
          <div className={styles.providerRow}>
            <span className={styles.serviceIcon}>{provider?.playback_ready ? <CheckCircle2 /> : provider?.oauth_connected ? <ShieldCheck /> : <Cloud />}</span>
            <span><strong>{providerTitle}</strong><small>YouTube Music et lecture publique</small></span>
            {isAuthenticated ? (
              <Button size="sm" onClick={() => connectProvider.mutate()} disabled={connectProvider.isPending || (!provider?.oauth_available && !provider?.oauth_connected && !provider?.playback_ready)}>
                {connectProvider.isPending ? <LoaderCircle className="spin" size={15} /> : <Radio size={15} />} Gérer
              </Button>
            ) : <Link href="/login">Connexion</Link>}
          </div>
          {providerNotice && <p className={styles.notice}>{providerNotice}</p>}
          <SharedSessionPanel compact />
        </details>
      </div>

      <CreatePlaylistSheet
        open={createOpen}
        pending={createPlaylist.isPending}
        error={createPlaylist.error instanceof Error ? createPlaylist.error.message : ""}
        onClose={() => setCreateOpen(false)}
        onCreate={(name) => createPlaylist.mutate(name)}
      />

      <Dialog open={Boolean(oauthUrl)} onOpenChange={(open) => { if (!open) setOauthUrl(""); }}>
        <DialogContent aria-label="Connexion Google" closeLabel="Fermer la connexion Google" className="w-[min(100%,32rem)]">
          <DialogHeader><DialogTitle>Associer YouTube Music</DialogTitle></DialogHeader>
          <DialogBody><DialogDescription>Une fenêtre Google va s’ouvrir. Après validation, MusicGlass reviendra ici.</DialogDescription></DialogBody>
          <DialogFooter><DialogClose render={<Button variant="secondary" />}>Annuler</DialogClose><Button onClick={openGoogleOAuth}><ExternalLink size={17} /> Ouvrir Google</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </main>
  );
}

function SectionTitle({ kicker, title }: { kicker: string; title: string }) {
  return <div className={styles.sectionTitle}><span>{kicker}</span><h2>{title}</h2></div>;
}

function MediaRail({ kicker, title, items }: { kicker: string; title: string; items: Array<{ title: string; subtitle: string; artwork: string; color: string }> }) {
  return <section className={styles.section}><SectionTitle kicker={kicker} title={title} /><div className={styles.rail}>{items.map((item, index) => <article className={styles.card} key={`${item.title}-${index}`}><Cover {...item} size="card" /><strong>{item.title}</strong><small>{item.subtitle}</small></article>)}</div></section>;
}

function Cover({ title, artwork, color, size }: { title: string; artwork?: string; color?: string; size: "card" | "row" }) {
  return <span className={`${styles.cover} ${size === "card" ? styles.cardCover : styles.rowCover}`} style={{ background: color || coverGradients[0] }}>{artwork ? (
    // Remote artwork hosts are dynamic and already proxied/fallback-managed by the backend.
    // eslint-disable-next-line @next/next/no-img-element
    <img src={artwork} alt="" />
  ) : <span>{title.slice(0, 1).toUpperCase()}</span>}</span>;
}

function EmptyState({ text }: { text: string }) {
  return <p className={styles.empty}>{text}</p>;
}

function LibrarySkeleton() {
  return <div className={styles.skeleton} aria-label="Chargement de la bibliothèque">{[0, 1].map((section) => <section key={section}><Skeleton className="h-5 w-40" /><div>{[0, 1, 2].map((item) => <Skeleton key={item} className="h-32 w-32" />)}</div></section>)}</div>;
}
