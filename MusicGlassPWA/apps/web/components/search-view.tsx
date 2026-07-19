"use client";

import { ArrowUpRight, History, Play, Search, Trash2 } from "lucide-react";
import { Badge } from "@appica/ui-react/badge";
import { Button } from "@appica/ui-react/button";
import { ButtonGroup } from "@appica/ui-react/button-group";
import { Input } from "@appica/ui-react/input";
import { ScrollArea } from "@appica/ui-react/scroll-area";
import { Skeleton } from "@appica/ui-react/skeleton";
import { useState, useEffect, useMemo, useRef, type CSSProperties } from "react";
import { useQuery } from "@tanstack/react-query";
import Image from "next/image";
import { useRouter, useSearchParams } from "next/navigation";
import { fetchSearch } from "@/lib/api";
import { handleArtworkError } from "@/lib/artwork";
import { demoTracks, type Track } from "@/lib/catalog";
import { clearLocalSearchHistory, readLocalSearchHistory, recordLocalSearch } from "@/lib/search-history";
import { clearSearchHistory, fetchMe, fetchSearchHistory, recordSearchHistory } from "@/lib/session-api";
import { parseSearch, type SearchItem } from "@/lib/youtube";
import { usePlaybackStore } from "@/store/playback-store";
import styles from "./search-view.module.css";

const FILTERS = ["Tout", "Titres", "Albums", "Artistes"] as const;

function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value);
  useEffect(() => {
    const handler = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(handler);
  }, [value, delay]);
  return debouncedValue;
}

function getTypeLabel(type: string): string {
  switch (type) {
    case "track": return "Titre";
    case "video": return "Vidéo";
    case "album": return "Album";
    case "artist": return "Artiste";
    case "playlist": return "Playlist";
    case "episode": return "Épisode";
    default: return "Musique";
  }
}

function getArtist(item: SearchItem): string {
  const artist = item.artist?.trim();
  return artist && !/^artiste inconnu$/i.test(artist) ? artist : "";
}

export function SearchView() {
  const router = useRouter();
  const searchParams = useSearchParams();

  const initialQuery = searchParams.get("q") || "";
  const initialFilter = searchParams.get("filter") || "Tout";

  const [query, setQuery] = useState(initialQuery);
  const [filter, setFilter] = useState(initialFilter);
  const [recentSearches, setRecentSearches] = useState<string[]>([]);
  const recordedQueryRef = useRef("");
  const debouncedQuery = useDebounce(query, 500);
  const playTrack = usePlaybackStore((state) => state.playTrack);
  const { data: me, isFetched: authResolved } = useQuery({
    queryKey: ["me"],
    queryFn: fetchMe,
    retry: false,
    staleTime: 15_000,
  });

  const { data, isLoading, error } = useQuery({
    queryKey: ["search", debouncedQuery],
    queryFn: async () => {
      if (!debouncedQuery) return [];
      try {
        const rawData = await fetchSearch(debouncedQuery);
        return parseSearch(rawData, debouncedQuery);
      } catch {
        return demoTracks
          .filter((track) => `${track.title} ${track.artist}`.toLowerCase().includes(debouncedQuery.toLowerCase()))
          .map((track) => ({
            id: track.id,
            title: track.title,
            artist: track.artist,
            type: "track" as const,
            artwork: track.artwork,
            duration: track.duration,
          }));
      }
    },
    enabled: debouncedQuery.length > 0,
  });

  const filteredResults = useMemo(() => (data || []).filter((item) => {
    if (filter === "Tout") return true;
    if (filter === "Titres") return item.type === "track" || item.type === "video";
    if (filter === "Albums") return item.type === "album";
    if (filter === "Artistes") return item.type === "artist";
    return true;
  }), [data, filter]);

  const resultGroups = useMemo(() => ({
    artists: filteredResults.filter((item) => item.type === "artist"),
    tracks: filteredResults.filter((item) => item.type === "track" || item.type === "video"),
    collections: filteredResults.filter((item) => item.type === "album" || item.type === "playlist"),
    others: filteredResults.filter((item) => item.type === "episode" || item.type === "unknown"),
  }), [filteredResults]);

  useEffect(() => {
    setRecentSearches(readLocalSearchHistory());
  }, []);

  useEffect(() => {
    if (!authResolved) return;
    if (!me) {
      setRecentSearches(readLocalSearchHistory());
      return;
    }

    let cancelled = false;
    const synchronizeHistory = async () => {
      const localHistory = readLocalSearchHistory();
      try {
        // Oldest first preserves the guest ordering after server-side promotion.
        for (const localQuery of [...localHistory].reverse()) {
          await recordSearchHistory(localQuery);
        }
        clearLocalSearchHistory();
        const serverHistory = await fetchSearchHistory();
        if (!cancelled) setRecentSearches(serverHistory.map((entry) => entry.query));
      } catch {
        if (!cancelled) setRecentSearches(localHistory);
      }
    };
    void synchronizeHistory();
    return () => {
      cancelled = true;
    };
  }, [authResolved, me]);

  useEffect(() => {
    const normalized = debouncedQuery.replace(/\s+/g, " ").trim();
    if (!normalized || isLoading || !data || recordedQueryRef.current.toLocaleLowerCase("fr") === normalized.toLocaleLowerCase("fr")) return;
    recordedQueryRef.current = normalized;
    setRecentSearches((history) => [normalized, ...history.filter((item) => item.toLocaleLowerCase("fr") !== normalized.toLocaleLowerCase("fr"))].slice(0, me ? 20 : 12));
    if (me) {
      void recordSearchHistory(normalized).catch(() => undefined);
    } else if (authResolved) {
      recordLocalSearch(normalized);
    }
  }, [authResolved, data, debouncedQuery, isLoading, me]);

  const eraseHistory = async () => {
    setRecentSearches([]);
    if (me) {
      await clearSearchHistory().catch(() => undefined);
    } else {
      clearLocalSearchHistory();
    }
  };

  const handlePlay = (item: SearchItem, playableQueue: Track[] = []) => {
    if (item.type !== "track" && item.type !== "video") return;

    const track = {
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: "",
      artwork: item.artwork,
      duration: item.duration || 0,
      accent: "#263443",
    };

    // Search results are matches, not a coherent playlist. Let YouTube Music's
    // AutoMix build the queue from the selected song instead.
    playTrack(track, playableQueue.length ? playableQueue : [track]);
  };

  const handleResultNavigation = (item: SearchItem) => {
    if (item.type === "artist") router.push(`/artist/${item.id}`);
    if (item.type === "album") router.push(`/album/${item.id}`);
    if (item.type === "playlist") router.push(`/playlist/${item.id}`);
  };

  const renderTrackRow = (item: SearchItem) => {
    const artist = getArtist(item);
    const typeLabel = getTypeLabel(item.type);

    return (
      <article key={item.id} className={styles.trackRow}>
        <Button
          type="button"
          variant="ghost"
          className={styles.trackArtwork}
          onClick={() => handlePlay(item)}
          aria-label={`Lire ${item.title}${artist ? ` de ${artist}` : ""}`}
        >
          <Image src={item.artwork} alt="" fill sizes="54px" unoptimized onError={handleArtworkError} />
          <span className={styles.playOverlay} aria-hidden><Play size={19} fill="currentColor" /></span>
        </Button>
        <div className={styles.trackMeta}>
          <strong>{item.title}</strong>
          <span>{artist || typeLabel}</span>
        </div>
        <Badge variant="soft" size="xs" className={styles.typeBadge}>{typeLabel}</Badge>
      </article>
    );
  };

  const renderArtistCard = (item: SearchItem, index: number) => (
    <Button
      type="button"
      variant="ghost"
      key={item.id}
      className={styles.artistCard}
      onClick={() => handleResultNavigation(item)}
      style={{ "--item-delay": `${Math.min(index, 7) * 35}ms` } as CSSProperties}
    >
      <span className={styles.artistArtwork}>
        <Image src={item.artwork} alt="" fill sizes="(max-width: 799px) 33vw, 180px" unoptimized onError={handleArtworkError} />
        <span className={styles.artistArrow} aria-hidden><ArrowUpRight size={18} /></span>
      </span>
      <strong>{item.title}</strong>
      <span>{getArtist(item) || "Artiste"}</span>
    </Button>
  );

  const renderCollectionCard = (item: SearchItem, index: number) => (
    <Button
      type="button"
      variant="ghost"
      key={item.id}
      className={styles.collectionCard}
      onClick={() => handleResultNavigation(item)}
      style={{ "--item-delay": `${Math.min(index, 7) * 35}ms` } as CSSProperties}
    >
      <span className={styles.collectionArtwork}>
        <Image src={item.artwork} alt="" fill sizes="(max-width: 799px) 50vw, 220px" unoptimized onError={handleArtworkError} />
        <span className={styles.collectionArrow} aria-hidden><ArrowUpRight size={18} /></span>
      </span>
      <span className={styles.collectionMeta}>
        <strong>{item.title}</strong>
        <span>{[getTypeLabel(item.type), getArtist(item)].filter(Boolean).join(" · ")}</span>
      </span>
    </Button>
  );

  const renderGroupedResults = () => {
    if (filter === "Artistes") {
      return <div className={styles.artistGrid}>{resultGroups.artists.map(renderArtistCard)}</div>;
    }
    if (filter === "Albums") {
      return <div className={styles.collectionGrid}>{resultGroups.collections.map(renderCollectionCard)}</div>;
    }
    if (filter === "Titres") {
      return <div className={styles.trackList}>{resultGroups.tracks.map(renderTrackRow)}</div>;
    }

    return (
      <div className={styles.resultGroups}>
        {resultGroups.artists.length > 0 && (
          <section className={styles.resultSection} aria-labelledby="search-artists-title">
            <div className={styles.groupHeading}>
              <div><span>Profils</span><h3 id="search-artists-title">Artistes</h3></div>
              <span>{resultGroups.artists.length}</span>
            </div>
            <div className={styles.artistGrid}>{resultGroups.artists.map(renderArtistCard)}</div>
          </section>
        )}
        {resultGroups.tracks.length > 0 && (
          <section className={styles.resultSection} aria-labelledby="search-tracks-title">
            <div className={styles.groupHeading}>
              <div><span>À écouter</span><h3 id="search-tracks-title">Titres</h3></div>
              <span>{resultGroups.tracks.length}</span>
            </div>
            <div className={styles.trackList}>{resultGroups.tracks.map(renderTrackRow)}</div>
          </section>
        )}
        {resultGroups.collections.length > 0 && (
          <section className={styles.resultSection} aria-labelledby="search-collections-title">
            <div className={styles.groupHeading}>
              <div><span>À découvrir</span><h3 id="search-collections-title">Albums & playlists</h3></div>
              <span>{resultGroups.collections.length}</span>
            </div>
            <div className={styles.collectionGrid}>{resultGroups.collections.map(renderCollectionCard)}</div>
          </section>
        )}
        {resultGroups.others.length > 0 && (
          <section className={styles.resultSection} aria-labelledby="search-other-title">
            <div className={styles.groupHeading}>
              <div><span>Plus de résultats</span><h3 id="search-other-title">Autres</h3></div>
              <span>{resultGroups.others.length}</span>
            </div>
            <div className={styles.passiveList}>
              {resultGroups.others.map((item) => (
                <div key={item.id} className={styles.passiveResult}>
                  <Image src={item.artwork} alt="" width={48} height={48} unoptimized onError={handleArtworkError} />
                  <span><strong>{item.title}</strong><small>{getArtist(item) || getTypeLabel(item.type)}</small></span>
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    );
  };

  const hasResults = filteredResults.length > 0;

  return (
    <main className={`page ${styles.searchPage}`} aria-labelledby="search-page-title">
      <header className={styles.hero}>
        <div className={styles.heroCopy}>
          <span className={styles.eyebrow}>Explorer le catalogue</span>
          <h1 id="search-page-title">Recherche</h1>
          <p>Un artiste, un album ou ce titre que vous avez en tête.</p>
        </div>
        <label className={styles.searchField}>
          <span className={styles.srOnly}>Rechercher dans le catalogue</span>
          <Input
            className={styles.searchBox}
            inputSize="lg"
            startSlot={<Search size={23} aria-hidden />}
            clearable={Boolean(query)}
            onClear={() => setQuery("")}
            value={query}
            inputProps={{ className: styles.searchNative }}
            onInput={(event) => setQuery(event.currentTarget.value)}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Que voulez-vous écouter ?"
            aria-label="Rechercher dans le catalogue"
          />
        </label>
      </header>

      {query && (
        <nav className={styles.filterNav} aria-label="Filtrer les résultats">
          <ScrollArea orientation="horizontal" scrollbarVisibility="never" className={styles.filterScroll}>
            <ButtonGroup className={styles.filters}>
              {FILTERS.map((filterName) => (
                <Button
                  type="button"
                  variant="ghost"
                  key={filterName}
                  className={filter === filterName ? styles.activeFilter : ""}
                  onClick={() => setFilter(filterName)}
                  aria-pressed={filter === filterName}
                >
                  {filterName}
                </Button>
              ))}
            </ButtonGroup>
          </ScrollArea>
        </nav>
      )}

      <section className={styles.content}>
        <div className={styles.sectionHeader}>
          <div>
            <span className={styles.eyebrow}>{query ? "Catalogue" : me ? "Synchronisé avec votre compte" : "Conservé sur cet appareil"}</span>
            <h2>{query ? `Résultats pour “${query}”` : "Recherches récentes"}</h2>
          </div>
          {!query && recentSearches.length > 0 && (
            <Button type="button" variant="outline" size="sm" className={styles.clearHistory} onClick={() => void eraseHistory()}>
              <Trash2 size={15} aria-hidden />
              Effacer
            </Button>
          )}
          {query && !isLoading && (
            <span className={styles.resultCount} aria-live="polite">
              {filteredResults.length} {filteredResults.length > 1 ? "résultats" : "résultat"}
            </span>
          )}
        </div>

        {!query && (
          <div className={styles.history} aria-label="Recherches récentes">
            {recentSearches.length > 0 ? recentSearches.map((recentQuery, index) => (
              <Button
                type="button"
                variant="outline"
                key={recentQuery.toLocaleLowerCase("fr")}
                onClick={() => setQuery(recentQuery)}
                style={{ "--item-delay": `${Math.min(index, 7) * 35}ms` } as CSSProperties}
              >
                <span className={styles.historyIcon}><History size={18} aria-hidden /></span>
                <span>{recentQuery}</span>
                <ArrowUpRight size={17} aria-hidden />
              </Button>
            )) : (
              <div className={styles.emptyHistory}>
                <span><History size={23} aria-hidden /></span>
                <div>
                  <strong>Votre historique apparaîtra ici</strong>
                  <p>Lancez une recherche pour retrouver vos artistes et albums en un geste.</p>
                </div>
              </div>
            )}
          </div>
        )}

        {isLoading && query && (
          <div className={styles.loadingList} aria-label="Chargement des résultats">
            {Array.from({ length: 6 }).map((_, index) => (
              <div className={styles.skeletonRow} key={index}>
                <Skeleton className={styles.skeletonArtwork} />
                <div><Skeleton /><Skeleton /></div>
              </div>
            ))}
          </div>
        )}

        {error && <div className={styles.notice}>Recherche en mode local temporaire.</div>}

        {query && !isLoading && hasResults && renderGroupedResults()}

        {query && !isLoading && !hasResults && (
          <div className={styles.noResults}>
            <Search size={25} aria-hidden />
            <div>
              <strong>Aucun résultat pour “{query}”</strong>
              <p>Essayez un titre plus court, un artiste ou le nom d’un album.</p>
            </div>
          </div>
        )}
      </section>
    </main>
  );
}
