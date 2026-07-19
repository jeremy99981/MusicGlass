import { ChevronDown } from "lucide-react";
import { Button } from "@appica/ui-react/button";
import { usePlaybackStore } from "@/store/playback-store";

export function PlayerHeader({ eyebrow, title }: { eyebrow: string; title: string }) {
  const setPlayerOpen = usePlaybackStore((state) => state.setPlayerOpen);

  return (
    <header className="fp-header">
      <Button variant="ghost" className="fp-close" onClick={() => setPlayerOpen(false)} aria-label="Réduire le lecteur">
        <ChevronDown size={28} />
      </Button>
      <span className="fp-header-label">
        <small>{eyebrow}</small>
        <strong>{title}</strong>
      </span>
      <span className="fp-header-spacer" aria-hidden="true" />
    </header>
  );
}
