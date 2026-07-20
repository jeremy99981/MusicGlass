"use client";

import { useQuery } from "@tanstack/react-query";
import { Avatar, AvatarFallback } from "@appica/ui-react/avatar";
import { Button } from "@appica/ui-react/button";
import { ButtonGroup } from "@appica/ui-react/button-group";
import { ScrollArea } from "@appica/ui-react/scroll-area";
import { Skeleton } from "@appica/ui-react/skeleton";
import { motion } from "motion/react";
import { ArrowRight, Play, Settings2, Sparkles } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type CSSProperties, useState } from "react";
import styles from "./home-view.module.css";
import { fetchHome } from "@/lib/api";
import { handleArtworkError } from "@/lib/artwork";
import { collections, demoTracks } from "@/lib/catalog";
import { type HomeItem, parseHome } from "@/lib/youtube";
import { usePlaybackStore } from "@/store/playback-store";

const fallbackHome = {
  sections: [
    {
      title: "Mix rapides",
      items: demoTracks.map((track) => ({
        id: track.id,
        title: track.title,
        subtitle: track.artist,
        artwork: track.artwork,
        duration: track.duration,
        type: "track" as const,
      })),
    },
    {
      title: "Playlists pour vous",
      items: collections.map((collection) => ({
        id: collection.title,
        title: collection.title,
        subtitle: collection.subtitle,
        artwork: "",
        type: "playlist" as const,
      })),
    },
  ],
};

function getGreeting(): { label: string; greeting: string } {
  const now = new Date();
  const hour = now.getHours();
  const days = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"];
  const day = days[now.getDay()];
  const timeOfDay = hour >= 5 && hour < 12 ? "matin" : hour < 18 ? "après-midi" : "soir";
  const greeting = hour >= 5 && hour < 12 ? "Bonjour" : hour < 18 ? "Bon après-midi" : "Bonsoir";
  return { label: `${day} ${timeOfDay}`, greeting };
}

function uniqueBy<T>(values: T[], key: (value: T) => string) {
  const seen = new Set<string>();
  return values.filter((value) => {
    const id = key(value).trim().toLocaleLowerCase("fr");
    if (!id || seen.has(id)) return false;
    seen.add(id);
    return true;
  });
}

export function HomeView() {
  const router = useRouter();
  const playTrack = usePlaybackStore((state) => state.playTrack);
  const [homeFilter, setHomeFilter] = useState<"Tout" | "Musique" | "Playlists">("Tout");
  const { data, isLoading, error } = useQuery({
    queryKey: ["home"],
    queryFn: async () => {
      try {
        return parseHome(await fetchHome());
      } catch {
        return fallbackHome;
      }
    },
    placeholderData: fallbackHome,
  });

  const { greeting } = getGreeting();
  const matchesFilter = (item: HomeItem) => homeFilter === "Tout"
    || (homeFilter === "Musique" && item.type === "track")
    || (homeFilter === "Playlists" && item.type !== "track");
  const visibleSections = data?.sections
    .map((section) => ({ ...section, items: section.items.filter(matchesFilter) }))
    .filter((section) => section.items.length > 0) ?? [];
  const allItems = visibleSections.flatMap((section) => section.items);
  const featured = allItems.find((item) => item.type === "track" && item.artwork) ?? allItems.find((item) => item.artwork);
  const quickItems = allItems.filter((item) => item.artwork).slice(0, 6);
  const artistItems = uniqueBy(
    allItems.filter((item) => item.type === "artist" || (item.type === "track" && item.subtitle && item.artwork)),
    (item) => item.type === "artist" ? item.title : item.subtitle,
  ).slice(0, 8);

  const handleItemClick = (item: HomeItem) => {
    if (item.type === "track") {
      playTrack({
        id: item.id,
        title: item.title,
        artist: item.subtitle,
        album: "",
        artwork: item.artwork,
        duration: item.duration || 0,
        accent: "#176bc1",
      });
      return;
    }
    const route = item.type === "artist" ? "artist" : item.type === "album" ? "album" : "playlist";
    router.push(`/${route}/${encodeURIComponent(item.id)}`);
  };

  if (isLoading) {
    return (
      <div className={`page home-page ${styles.page} ${styles.loading}`} aria-label="Chargement de l’accueil">
        <Skeleton className={styles.loadingHeader} />
        <Skeleton className={styles.loadingHero} />
        <div className={styles.loadingRail}>{Array.from({ length: 5 }).map((_, index) => <Skeleton key={index} />)}</div>
      </div>
    );
  }

  if (error || !data || !featured) {
    return <div className={`page home-page ${styles.page} ${styles.error}`}>Chargement impossible pour le moment.</div>;
  }

  return (
    <div className={`page home-page ${styles.page}`}>
      <header className={styles.topbar}>
        <div className={styles.topbarCopy}>
          <span className={styles.day} suppressHydrationWarning>{greeting}</span>
          <h1>Écouter</h1>
        </div>
        <div className={styles.topbarActions}>
          <Avatar className={styles.avatar} aria-hidden="true">
            <AvatarFallback>MG</AvatarFallback>
          </Avatar>
          <Link className={styles.settings} href="/settings" aria-label="Réglages"><Settings2 size={20} /></Link>
        </div>
      </header>

      <section
        className={styles.feature}
        style={{ "--feature-artwork": `url(${featured.artwork})` } as CSSProperties}
        aria-labelledby="home-feature-title"
      >
        <div className={styles.featureBackdrop} aria-hidden="true" />
        <motion.div className={styles.featureCopy} initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.4 }}>
          <span className={styles.featureKicker} suppressHydrationWarning><Sparkles size={14} /> {greeting}, votre sélection est prête</span>
          <h2 id="home-feature-title">{featured.title}</h2>
          <p>{featured.subtitle || "Une sélection pensée pour votre écoute"}</p>
          <Button type="button" onClick={() => handleItemClick(featured)}>
            <Play size={19} fill="currentColor" /> Écouter
          </Button>
        </motion.div>
      </section>

      <ButtonGroup className={styles.filters} aria-label="Filtres de l’accueil">
        {(["Tout", "Musique", "Playlists"] as const).map((value) => (
          <Button key={value} variant="ghost" className={homeFilter === value ? styles.activeFilter : ""} aria-pressed={homeFilter === value} onClick={() => setHomeFilter(value)}>{value}</Button>
        ))}
      </ButtonGroup>

      <section className={styles.quickSection} aria-labelledby="quick-title">
        <div className={styles.sectionHeading}>
          <div><span>Reprendre en un geste</span><h2 id="quick-title">Vos raccourcis</h2></div>
          <ArrowRight size={18} aria-hidden="true" />
        </div>
        <motion.div className={`home-quick-grid ${styles.quickGrid}`} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.38 }}>
          {quickItems.map((item) => (
            <Button variant="ghost" key={`quick-${item.type}-${item.id}`} onClick={() => handleItemClick(item)}>
              <Image src={item.artwork} alt="" width={82} height={82} unoptimized onError={handleArtworkError} />
              <div className={styles.quickCopy}><strong>{item.title}</strong><small>{item.subtitle}</small></div>
              <i aria-hidden="true"><Play size={15} fill="currentColor" /></i>
            </Button>
          ))}
        </motion.div>
      </section>

      {artistItems.length > 0 && (
        <section className={styles.artistSection} aria-labelledby="artists-title">
          <div className={styles.sectionHeading}>
            <div><span>Votre constellation</span><h2 id="artists-title">Artistes à retrouver</h2></div>
            <ArrowRight size={18} aria-hidden="true" />
          </div>
          <ScrollArea orientation="horizontal" scrollbarVisibility="never" className={styles.artistScroll}>
            <div className={styles.artistRail}>
              {artistItems.map((item) => {
                const artistName = item.type === "artist" ? item.title : item.subtitle;
                return (
                  <Button variant="ghost" key={`artist-${item.id}`} onClick={() => handleItemClick(item)} aria-label={item.type === "artist" ? `Ouvrir ${artistName}` : `Écouter ${item.title} de ${artistName}`}>
                    <span className="aspect-square"><Image src={item.artwork} alt="" width={160} height={160} unoptimized onError={handleArtworkError} /></span>
                    <strong>{artistName}</strong>
                  </Button>
                );
              })}
            </div>
          </ScrollArea>
        </section>
      )}

      <motion.div className={`shelves ${styles.shelves}`} initial={{ opacity: 0, y: 18 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.45 }}>
        {visibleSections.map((section, sectionIndex) => (
          <section key={section.title} className={`shelf ${styles.shelf}`}>
            <div className={styles.sectionHeading}>
              <div><span>{sectionIndex === 0 ? "Choisi pour vous" : "Explorez autrement"}</span><h2>{section.title}</h2></div>
              <Link className={styles.collectionLink} href={`/collection?title=${encodeURIComponent(section.title)}`} aria-label={`Voir toute la collection ${section.title}`}>
                <ArrowRight size={20} aria-hidden="true" />
              </Link>
            </div>
            <ScrollArea orientation="horizontal" scrollbarVisibility="never" className={styles.cardScroll}>
              <div className={`shelf-scroll ${styles.cardRail}`}>
                {section.items.map((item) => (
                  <Button variant="ghost" key={`${section.title}-${item.type}-${item.id}`} className={`shelf-card ${styles.card}`} onClick={() => handleItemClick(item)}>
                    <span className={`shelf-card-art ${styles.cardArtwork}`}>
                      {item.artwork
                        ? <Image src={item.artwork} alt="" width={320} height={320} unoptimized onError={handleArtworkError} />
                        : <span className={styles.placeholder} aria-hidden="true"><Sparkles size={24} /></span>}
                      <i aria-hidden="true"><Play size={18} fill="currentColor" /></i>
                    </span>
                    <strong className="shelf-card-title">{item.title}</strong>
                    <small className="shelf-card-subtitle">{item.subtitle}</small>
                  </Button>
                ))}
              </div>
            </ScrollArea>
          </section>
        ))}
      </motion.div>
    </div>
  );
}
