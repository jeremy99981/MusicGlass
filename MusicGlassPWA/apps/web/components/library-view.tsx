"use client";

import { useEffect, useState } from "react";
import { Badge } from "@appica/ui-react/badge";
import { Button } from "@appica/ui-react/button";
import { Dialog, DialogBody, DialogClose, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@appica/ui-react/dialog";
import { Input } from "@appica/ui-react/input";
import { Skeleton } from "@appica/ui-react/skeleton";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CheckCircle2, Cloud, ExternalLink, Heart, LoaderCircle, Music2, Plus, Radio, ShieldCheck, WifiOff } from "lucide-react";
import Link from "next/link";
import { connectYouTubeProvider, createLibraryPlaylist, fetchLibrary } from "@/lib/api";
import { collections } from "@/lib/catalog";
import { SharedSessionPanel } from "./shared-session-panel";

export function LibraryView() {
  const queryClient = useQueryClient();
  const [playlistName, setPlaylistName] = useState("");
  const [oauthUrl, setOauthUrl] = useState("");
  const [providerNotice, setProviderNotice] = useState("");
  const library = useQuery({
    queryKey: ["library"],
    queryFn: fetchLibrary,
    retry: false,
  });

  const createPlaylist = useMutation({
    mutationFn: createLibraryPlaylist,
    onSuccess: () => {
      setPlaylistName("");
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
  const fallbackPlaylists = collections.concat(collections).slice(0, 4);
  const isAuthenticated = !library.isError;
  const providerTitle = !isAuthenticated
    ? "Connectez MusicGlass"
    : provider?.playback_ready
      ? "Lecture publique prête"
      : provider?.oauth_connected
        ? "Compte Google lié"
        : provider?.oauth_available
          ? "Connexion privée disponible"
          : "Lecture publique sans compte";
  const providerText = !isAuthenticated
    ? "Connectez MusicGlass pour retrouver les likes et playlists enregistrés dans notre backend."
    : provider?.playback_ready
      ? "Le backend possède des credentials serveur. Les flux privés et publics peuvent être résolus côté API."
      : provider?.oauth_connected
        ? "Compte Google lié. Les données privées YouTube Music demandent encore une résolution fournisseur autorisée côté serveur."
        : provider?.oauth_available
          ? "La PWA peut ouvrir Google, mais elle ne peut pas lire les cookies YouTube Music natifs comme Flutter/Metrolist. La synchro privée dépend du backend."
          : "Metrolist récupère les likes/playlists privés via WebView native et cookies SAPISID. En PWA, on garde la lecture publique et les likes/playlists MusicGlass backend.";

  const openGoogleOAuth = () => {
    if (!oauthUrl) return;
    const popup = window.open(oauthUrl, "musicglass-youtube-oauth", "popup=yes,width=520,height=720");
    if (!popup) {
      window.location.href = oauthUrl;
      return;
    }
    popup.focus();
  };

  return (
    <div className="page library-page">
      <header className="topbar">
        <div>
          <span className="eyebrow">Votre univers</span>
          <h1>Bibliothèque</h1>
        </div>
        <Button variant="ghost" size="icon-md" className="round-action" onClick={() => setPlaylistName((value) => value || "Nouvelle playlist")}>
          <Plus />
        </Button>
      </header>

      {library.isError && (
        <section className="library-auth-card">
          <WifiOff />
          <div>
            <strong>Connectez-vous pour synchroniser votre bibliothèque.</strong>
            <p>Vos likes et playlists MusicGlass sont sauvegardés dans le backend dès que votre compte est actif.</p>
          </div>
          <Link href="/login">Connexion</Link>
        </section>
      )}

      <section className={`provider-card ${provider?.connected ? "provider-card-connected" : ""}`}>
        <div className="provider-icon">{provider?.playback_ready ? <CheckCircle2 /> : provider?.oauth_connected ? <ShieldCheck /> : <Cloud />}</div>
        <div>
          <Badge variant="soft" size="sm">Fournisseur musique</Badge>
          <strong>{providerTitle}</strong>
          <p>{providerText}</p>
        </div>
        {isAuthenticated ? (
          <Button
            variant="primary"
            onClick={() => {
              connectProvider.mutate();
            }}
            disabled={connectProvider.isPending || (!provider?.oauth_available && !provider?.oauth_connected && !provider?.playback_ready)}
          >
            {connectProvider.isPending ? <LoaderCircle className="spin" size={17} /> : <Radio size={17} />}
            {provider?.oauth_connected ? "Vérifier" : provider?.oauth_available ? "Synchroniser" : provider?.playback_ready ? "Prêt" : "Privé indisponible"}
          </Button>
        ) : (
          <Link href="/login">Connexion</Link>
        )}
      </section>

      {(providerNotice || connectProvider.data?.status === "server_setup_required") && (
        <div className="library-warning">
          {providerNotice ||
            "Les likes/playlists privés YouTube Music nécessitent une authentification fournisseur réelle. La lecture publique reste disponible sans compte."}
        </div>
      )}
      <Dialog open={Boolean(oauthUrl)} onOpenChange={(open) => { if (!open) setOauthUrl(""); }}>
        <DialogContent aria-label="Connexion Google" closeLabel="Fermer la connexion Google" className="w-[min(100%,32rem)]">
          <DialogHeader>
            <Badge variant="soft" size="sm" className="w-fit">Connexion Google</Badge>
            <DialogTitle>Associer YouTube Music</DialogTitle>
          </DialogHeader>
          <DialogBody>
            <DialogDescription>Une fenêtre Google va s’ouvrir. Une fois validée, MusicGlass reviendra automatiquement ici.</DialogDescription>
          </DialogBody>
          <DialogFooter>
            <DialogClose render={<Button variant="secondary" />}>Annuler</DialogClose>
            <Button onClick={openGoogleOAuth}><ExternalLink size={17} /> Ouvrir Google</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <section className="library-session-card">
        <div className="library-session-copy">
          <span>Écoute ensemble</span>
          <h2>Session partagée</h2>
          <p>Créez une session ou rejoignez un ami depuis votre bibliothèque, sans polluer l’accueil.</p>
        </div>
        <SharedSessionPanel />
      </section>

      <div className="stat-grid">
        <article>
          <Heart fill="currentColor" />
          <strong>{library.isLoading ? <Skeleton className="h-8 w-12" aria-label="Chargement des titres aimés" /> : likes.length}</strong>
          <span>Titres aimés</span>
        </article>
        <article>
          <Music2 />
          <strong>{library.isLoading ? <Skeleton className="h-8 w-12" aria-label="Chargement des playlists" /> : playlists.length}</strong>
          <span>Playlists</span>
        </article>
      </div>

      {likes[0] && (
        <section className="library-liked-strip">
          <span>Dernier like</span>
          <strong>{likes[0].song.title}</strong>
          <small>{likes[0].song.artist}</small>
        </section>
      )}

      <section className="library-create">
        <div>
          <h2>Créer une playlist</h2>
          <p>Ajoutez ensuite des titres depuis le lecteur ou les résultats de recherche.</p>
        </div>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            const name = playlistName.trim();
            if (name) createPlaylist.mutate(name);
          }}
        >
          <Input value={playlistName} onChange={(event) => setPlaylistName(event.target.value)} placeholder="Nom de playlist" aria-label="Nom de playlist" />
          <Button type="submit" disabled={createPlaylist.isPending || playlistName.trim().length === 0}>
            {createPlaylist.isPending ? "Création..." : "Créer"}
          </Button>
        </form>
      </section>

      <div className="section-header">
        <h2>Playlists</h2>
        <Button variant="ghost" onClick={() => setPlaylistName("Nouvelle playlist")}>Nouvelle playlist</Button>
      </div>
      <div className="library-grid">
        {(playlists.length ? playlists : fallbackPlaylists).map((item, index) => {
          const isBackendPlaylist = "name" in item;
          const title = isBackendPlaylist ? item.name : item.title;
          const subtitle = isBackendPlaylist ? `${item.song_count ?? 0} titres` : item.subtitle;
          const color = isBackendPlaylist ? "linear-gradient(145deg,#263443,#8bb7aa)" : item.color;
          return (
            <article key={`${title}-${index}`}>
              <div className="library-cover" style={{ background: color }}>
                <span>{String(index + 1).padStart(2, "0")}</span>
              </div>
              <strong>{title}</strong>
              <small>{subtitle}</small>
            </article>
          );
        })}
      </div>

      <div className="section-header library-liked-header">
        <h2>Derniers likes</h2>
      </div>
      <div className="library-liked-list">
        {likes.slice(0, 6).map((like) => (
          <article key={like.id}>
            <div className="library-like-cover">
              {like.song.cover_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={like.song.cover_url} alt="" />
              ) : (
                <Heart size={18} fill="currentColor" />
              )}
            </div>
            <div>
              <strong>{like.song.title}</strong>
              <span>{like.song.artist}</span>
            </div>
          </article>
        ))}
        {!likes.length && !library.isLoading && <p className="library-empty">Aucun like pour le moment. Touchez le cœur dans le lecteur pour sauvegarder un titre.</p>}
      </div>
    </div>
  );
}
