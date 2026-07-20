"use client";

import { useEffect, useState } from "react";

/**
 * Rendu par fenêtre piloté par le défilement. On ne monte d'abord que `batch`
 * lignes (≈ ce qu'un écran affiche), puis on en ajoute un lot **uniquement quand
 * l'utilisateur approche du bas** de ce qui est déjà rendu. La liste complète
 * n'est donc jamais montée tant qu'on ne l'a pas parcourue : le rendu initial est
 * constant quelle que soit la longueur totale.
 *
 * @param total     nombre total d'éléments
 * @param resetKey  change de valeur pour réinitialiser la fenêtre (ex: id de page)
 * @param batch     nombre d'éléments montés au départ et ajoutés à chaque lot
 * @param threshold distance (px) avant le bas à partir de laquelle on charge le lot suivant
 */
export function useWindowedList(total: number, resetKey: unknown, batch = 10, threshold = 400) {
  const [count, setCount] = useState(batch);

  useEffect(() => {
    setCount(batch);
  }, [resetKey, batch]);

  useEffect(() => {
    if (count >= total) return;

    const maybeLoadMore = () => {
      const scrolled = window.innerHeight + window.scrollY;
      const bottom = document.documentElement.scrollHeight;
      if (scrolled >= bottom - threshold) {
        setCount((current) => Math.min(current + batch, total));
      }
    };

    window.addEventListener("scroll", maybeLoadMore, { passive: true });
    window.addEventListener("resize", maybeLoadMore);
    // Complète le premier écran si les `batch` lignes ne le remplissent pas encore.
    maybeLoadMore();
    return () => {
      window.removeEventListener("scroll", maybeLoadMore);
      window.removeEventListener("resize", maybeLoadMore);
    };
  }, [count, total, batch, threshold]);

  return Math.min(count, total);
}
