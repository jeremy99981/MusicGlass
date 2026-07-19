"use client";

import { Button, Navigation, NavigationLink } from "@appica/ui-react";
import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { AudioLines, Clock3, Heart, Home, Library, ListMusic, Plus, Search, Settings2 } from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { FullPlayer } from "./full-player";
import { MiniPlayer } from "./mini-player";
import { QueueSheet } from "./player/queue-sheet";
import { SharedSessionPanel } from "./shared-session-panel";
import { usePlaybackStore } from "@/store/playback-store";

const items = [
  { href: "/", label: "Accueil", icon: Home },
  { href: "/search", label: "Recherche", icon: Search },
  { href: "/library", label: "Bibliothèque", icon: Library },
];

const mobileItems = [
  ...items,
  { href: "/settings", label: "Réglages", icon: Settings2 },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const reduceMotion = useReducedMotion();
  const current = usePlaybackStore((state) => state.current);
  const playerOpen = usePlaybackStore((state) => state.playerOpen);
  if (pathname === "/login") return <main>{children}</main>;
  return (
    <div className={`app-frame ${playerOpen ? "player-expanded" : ""}`}>
      <aside className="desktop-sidebar">
        <Link href="/" className="brand"><span className="brand-mark"><AudioLines size={20} /></span><span>MusicGlass</span></Link>
        <Navigation className="side-nav" orientation="vertical" variant="pill" size="md">
          {items.map(({ href, label, icon: Icon }) => (
            <NavigationLink
              key={href}
              render={<Link href={href} />}
              active={pathname === href}
              className={pathname === href ? "active" : ""}
            >
              <Icon size={21} />
              <span>{label}</span>
            </NavigationLink>
          ))}
        </Navigation>
        <section className="sidebar-library" aria-label="Raccourcis bibliothèque">
          <header>
            <span>Votre bibliothèque</span>
            <Button render={<Link href="/library" />} variant="ghost" size="icon-sm" aria-label="Créer une playlist">
              <Plus size={16} />
            </Button>
          </header>
          <Link href="/library"><Heart size={16} /><span><strong>Titres aimés</strong><small>Votre collection</small></span></Link>
          <Link href="/library"><ListMusic size={16} /><span><strong>Playlists</strong><small>Mix et sélections</small></span></Link>
          <Link href="/library"><Clock3 size={16} /><span><strong>Écoutés récemment</strong><small>Reprendre l’écoute</small></span></Link>
        </section>
        <SharedSessionPanel compact />
        <Link href="/settings" className="sidebar-settings"><Settings2 size={20} /> Réglages</Link>
      </aside>
      <motion.main
        key={pathname}
        className={`page-content ${current ? "has-player" : ""}`}
        initial={reduceMotion ? false : { opacity: 0.92, y: 7 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: reduceMotion ? 0 : 0.24, ease: [0.2, 0.8, 0.2, 1] }}
      >
        {children}
      </motion.main>
      {current && <MiniPlayer />}
      <Navigation className="mobile-nav" orientation="horizontal" variant="pill" size="sm">
        {mobileItems.map(({ href, label, icon: Icon }) => (
          <NavigationLink
            key={href}
            render={<Link href={href} />}
            active={pathname === href}
            className={pathname === href ? "active" : ""}
          >
            <Icon size={22} />
            <span>{label}</span>
          </NavigationLink>
        ))}
      </Navigation>
      <AnimatePresence>{playerOpen && <FullPlayer />}</AnimatePresence>
      {current && <QueueSheet />}
    </div>
  );
}
