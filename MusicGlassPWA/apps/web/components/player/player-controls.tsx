import { Pause, Play, Repeat2, Shuffle, SkipBack, SkipForward } from "lucide-react";
import { Button } from "@appica/ui-react/button";
import { usePlaybackStore } from "@/store/playback-store";
import { useSharedSessionStore } from "@/store/shared-session-store";

export function PlayerControls() {
  const isPlaying = usePlaybackStore((state) => state.isPlaying);
  const setPlaying = usePlaybackStore((state) => state.setPlaying);
  const next = usePlaybackStore((state) => state.next);
  const previous = usePlaybackStore((state) => state.previous);
  const shuffle = usePlaybackStore((state) => state.shuffle);
  const toggleShuffle = usePlaybackStore((state) => state.toggleShuffle);
  const repeat = usePlaybackStore((state) => state.repeat);
  const cycleRepeat = usePlaybackStore((state) => state.cycleRepeat);
  const { code, isHost } = useSharedSessionStore();
  const controlsLocked = Boolean(code && !isHost);
  const repeatLabel = repeat === "one" ? "Répéter ce titre" : repeat === "all" ? "Répéter la file" : "Répétition désactivée";

  return (
    <div className="fp-controls" role="group" aria-label="Contrôles de lecture">
      <Button
        variant="ghost"
        className={`fp-ctrl-btn ${shuffle ? "fp-ctrl-active" : ""}`}
        onClick={toggleShuffle}
        disabled={controlsLocked}
        aria-label="Aléatoire"
        aria-pressed={shuffle}
        title={controlsLocked ? "Contrôles réservés à l’hôte" : "Lecture aléatoire"}
      >
        <Shuffle size={20} />
      </Button>
      <Button variant="ghost" className="fp-ctrl-btn" onClick={previous} disabled={controlsLocked} aria-label="Titre précédent">
        <SkipBack size={24} fill="currentColor" />
      </Button>
      <Button
        variant="ghost"
        className="fp-play-btn"
        onClick={() => setPlaying(!isPlaying)}
        disabled={controlsLocked}
        aria-label={controlsLocked ? "Contrôles réservés à l’hôte" : isPlaying ? "Pause" : "Lecture"}
        aria-pressed={isPlaying}
      >
        {isPlaying ? <Pause size={28} fill="currentColor" /> : <Play size={28} fill="currentColor" />}
      </Button>
      <Button variant="ghost" className="fp-ctrl-btn" onClick={next} disabled={controlsLocked} aria-label="Titre suivant">
        <SkipForward size={24} fill="currentColor" />
      </Button>
      <Button
        variant="ghost"
        className={`fp-ctrl-btn ${repeat !== "off" ? "fp-ctrl-active" : ""}`}
        onClick={cycleRepeat}
        disabled={controlsLocked}
        aria-label={repeatLabel}
        aria-pressed={repeat !== "off"}
        title={controlsLocked ? "Contrôles réservés à l’hôte" : repeatLabel}
      >
        <Repeat2 size={20} />
        {repeat === "one" && <span className="fp-repeat-badge">1</span>}
      </Button>
    </div>
  );
}
