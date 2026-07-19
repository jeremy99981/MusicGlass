import type { SyntheticEvent } from "react";

export function handleArtworkError(event: SyntheticEvent<HTMLImageElement>) {
  const target = event.currentTarget;
  if (!target.dataset.retry && target.src.includes("hq720.jpg")) {
    target.dataset.retry = "hqdefault";
    target.src = target.src.replace("hq720.jpg", "hqdefault.jpg");
    return;
  }
  if (!target.dataset.retry && target.src.includes("=w1200-h1200")) {
    target.dataset.retry = "w540";
    target.src = target.src.replace("=w1200-h1200", "=w540-h540");
    return;
  }
  target.style.display = "none";
  target.parentElement?.classList.add("artwork-fallback");
}
