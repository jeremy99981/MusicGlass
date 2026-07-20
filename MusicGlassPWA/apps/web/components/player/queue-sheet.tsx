"use client";

import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { Button } from "@appica/ui-react/button";
import { useMediaQuery } from "@appica/ui-react/hooks/use-media-query";
import { Skeleton } from "@appica/ui-react/skeleton";
import { ChevronDown, GripHorizontal, Music2, Pause, Play, X } from "lucide-react";
import { useEffect, useId, useRef, useState } from "react";
import { handleArtworkError } from "@/lib/artwork";
import { usePlaybackStore } from "@/store/playback-store";
import { useSharedSessionStore } from "@/store/shared-session-store";

function QueueArtwork({ artwork }: { artwork: string }) {
  const [isLoaded, setIsLoaded] = useState(false);

  return (
    <span className="queue-artwork">
      {!isLoaded && <Skeleton className="queue-artwork-skeleton" />}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className={isLoaded ? "queue-artwork-loaded" : ""}
        src={artwork}
        alt=""
        onLoad={() => setIsLoaded(true)}
        onError={(event) => {
          handleArtworkError(event);
          if (event.currentTarget.style.display === "none") setIsLoaded(true);
        }}
      />
    </span>
  );
}

function RecommendationSkeletons() {
  return (
    <div className="queue-recommendation-skeletons" aria-hidden="true">
      {Array.from({ length: 3 }, (_, index) => (
        <div className="queue-row queue-skeleton-row" key={index}>
          <Skeleton className="queue-artwork-skeleton" />
          <span>
            <Skeleton className="queue-skeleton-title" />
            <Skeleton className="queue-skeleton-artist" />
          </span>
        </div>
      ))}
    </div>
  );
}

export function QueueSheet() {
  const reduceMotion = useReducedMotion();
  const dialogRef = useRef<HTMLElement>(null);
  const previouslyFocusedRef = useRef<HTMLElement | null>(null);
  const titleId = useId();
  const summaryId = useId();
  const isDocked = useMediaQuery("(min-width: 1280px)");
  const isMobile = useMediaQuery("(max-width: 1023px)");
  const queueOpen = usePlaybackStore((state) => state.queueOpen);
  const setQueueOpen = usePlaybackStore((state) => state.setQueueOpen);
  const queue = usePlaybackStore((state) => state.queue);
  const currentIndex = usePlaybackStore((state) => state.currentIndex);
  const isQueueLoading = usePlaybackStore((state) => state.isQueueLoading);
  const queueError = usePlaybackStore((state) => state.queueError);
  const isPlaying = usePlaybackStore((state) => state.isPlaying);
  const setPlaying = usePlaybackStore((state) => state.setPlaying);
  const sessionCode = useSharedSessionStore((state) => state.code);
  const isSessionHost = useSharedSessionStore((state) => state.isHost);
  const controlsLocked = Boolean(sessionCode && !isSessionHost);
  const playQueueIndex = usePlaybackStore((state) => state.playQueueIndex);
  const current = queue[currentIndex];
  const upcoming = queue
    .map((track, index) => ({ track, index }))
    .filter((item) => item.index > currentIndex);
  const queueSummary = `${queue.length} titre${queue.length > 1 ? "s" : ""} · ${upcoming.length} à suivre`;

  useEffect(() => {
    if (!queueOpen) return;

    previouslyFocusedRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    if (!window.matchMedia("(min-width: 1280px)").matches) dialogRef.current?.focus();

    return () => {
      previouslyFocusedRef.current?.focus();
      previouslyFocusedRef.current = null;
    };
  }, [queueOpen]);

  useEffect(() => {
    if (!queueOpen) return;
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      event.preventDefault();
      setQueueOpen(false);
    };
    document.addEventListener("keydown", handleEscape);
    return () => document.removeEventListener("keydown", handleEscape);
  }, [queueOpen, setQueueOpen]);

  const handleDialogKeyDown = (event: React.KeyboardEvent<HTMLElement>) => {
    if (event.key !== "Tab" || isDocked) return;

    const focusable = Array.from(
      event.currentTarget.querySelectorAll<HTMLElement>(
        'button:not(:disabled), [href], input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])',
      ),
    );
    if (focusable.length === 0) return;

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (document.activeElement === event.currentTarget) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  };

  return (
    <AnimatePresence>
      {queueOpen && (
        <motion.div className={`queue-backdrop ${isDocked ? "queue-docked" : ""}`} initial={reduceMotion ? false : { opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: reduceMotion ? 0 : 0.18 }}>
          <Button variant="ghost" className="queue-dismiss" aria-label="Fermer la file d’attente" onClick={() => setQueueOpen(false)} />
          <motion.section
            id="playback-queue"
            ref={dialogRef}
            className="queue-sheet"
            role="dialog"
            aria-modal={isDocked ? undefined : "true"}
            aria-labelledby={titleId}
            aria-describedby={summaryId}
            tabIndex={-1}
            onKeyDown={handleDialogKeyDown}
            initial={reduceMotion ? false : isMobile ? { opacity: 0 } : { opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            exit={reduceMotion || isMobile ? { opacity: 0 } : { opacity: 0, y: 8 }}
            drag={isMobile ? "y" : false}
            dragConstraints={{ top: 0, bottom: 0 }}
            dragElastic={{ top: 0, bottom: 0.42 }}
            onDragEnd={(_, info) => {
              if (info.offset.y > 90 || info.velocity.y > 600) setQueueOpen(false);
            }}
            transition={{ duration: reduceMotion ? 0 : 0.22, ease: [0.2, 0.8, 0.2, 1] }}
          >
            <Button variant="ghost" className="queue-handle" aria-label="Glisser ou toucher pour fermer la file d’attente" onClick={() => setQueueOpen(false)}>
              <GripHorizontal size={30} />
            </Button>
            <header className="queue-header">
              <div>
                <span id={summaryId}>{queueSummary}</span>
                <h2 id={titleId}>File d’attente</h2>
              </div>
              <Button variant="ghost" onClick={() => setQueueOpen(false)} aria-label="Fermer">
                <X size={20} />
              </Button>
            </header>

            <div className="queue-body">
              {current && (
                <section className="queue-section" aria-labelledby={`${summaryId}-current`}>
                  <p id={`${summaryId}-current`}>En cours</p>
                  <article className="queue-row queue-current" aria-current="true">
                    <QueueArtwork key={current.id} artwork={current.artwork} />
                    <div>
                      <strong>{current.title}</strong>
                      <span>{current.artist}</span>
                    </div>
                    <Music2 size={18} aria-hidden />
                  </article>
                </section>
              )}

              <section className="queue-section" aria-labelledby={`${summaryId}-upcoming`}>
                <p id={`${summaryId}-upcoming`}>À suivre · {upcoming.length} titre{upcoming.length > 1 ? "s" : ""}</p>
                {upcoming.length === 0 && !isQueueLoading ? (
                  <div className="queue-empty" role="status">Des recommandations vont être ajoutées automatiquement.</div>
                ) : (
                  <motion.div className="queue-list" role="list" layout={reduceMotion ? false : true}>
                    <AnimatePresence initial={false} mode="popLayout">
                      {upcoming.map(({ track, index }) => {
                        return (
                          <motion.article
                            key={track.id}
                            className="queue-row queue-row-actionable"
                            role="listitem"
                            layout={reduceMotion ? false : "position"}
                            initial={reduceMotion ? false : { opacity: 0, y: 8 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0, y: reduceMotion ? 0 : -6 }}
                            transition={{ duration: reduceMotion ? 0 : 0.18, delay: reduceMotion ? 0 : Math.min(index - currentIndex - 1, 7) * 0.025, ease: [0.2, 0.8, 0.2, 1] }}
                          >
                            <QueueArtwork artwork={track.artwork} />
                            <Button variant="ghost" className="queue-row-main" onClick={() => playQueueIndex(index)} aria-label={`Lire ${track.title}`}>
                              <strong>{track.title}</strong>
                              <span>{track.artist}</span>
                            </Button>
                          </motion.article>
                        );
                      })}
                    </AnimatePresence>
                  </motion.div>
                )}
                {isQueueLoading && (
                  <div className="queue-loading" role="status" aria-live="polite">
                    <span className="queue-loading-label">Recherche de titres proches...</span>
                    <RecommendationSkeletons />
                  </div>
                )}
                {queueError && <div className="queue-warning" role="alert">{queueError}</div>}
              </section>
            </div>
            {current && (
              <footer className="queue-mobile-footer">
                <Button variant="ghost" className="queue-mobile-now-playing" onClick={() => setQueueOpen(false)} aria-label="Revenir au lecteur en cours">
                  <QueueArtwork key={current.id} artwork={current.artwork} />
                  <span>
                    <small>Lecture en cours</small>
                    <strong>{current.title}</strong>
                  </span>
                  <ChevronDown size={20} aria-hidden="true" />
                </Button>
                <Button
                  variant="ghost"
                  className="queue-mobile-play"
                  onClick={() => setPlaying(!isPlaying)}
                  disabled={controlsLocked}
                  aria-label={controlsLocked ? "Contrôles réservés à l’hôte" : isPlaying ? "Pause" : "Lecture"}
                  aria-pressed={isPlaying}
                >
                  {isPlaying ? <Pause size={24} fill="currentColor" aria-hidden="true" /> : <Play size={24} fill="currentColor" aria-hidden="true" />}
                </Button>
              </footer>
            )}
          </motion.section>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
