import { usePlaybackStore } from "@/store/playback-store";
import { useSharedSessionStore } from "@/store/shared-session-store";

function formatTime(value: number) {
  const safe = Number.isFinite(value) ? value : 0;
  const m = Math.floor(safe / 60);
  const s = Math.floor(safe % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

export function PlayerTimeline() {
  const position = usePlaybackStore((state) => state.position);
  const duration = usePlaybackStore((state) => state.duration);
  const seekTo = usePlaybackStore((state) => state.seekTo);
  const { code, isHost } = useSharedSessionStore();
  const controlsLocked = Boolean(code && !isHost);

  const safePosition = duration > 0 ? Math.min(Math.max(position, 0), duration) : 0;
  const progress = duration > 0 ? (safePosition / duration) * 100 : 0;
  const positionLabel = formatTime(safePosition);
  const durationLabel = duration > 0 ? formatTime(duration) : "–:––";
  const remainingLabel = duration > 0 ? `-${formatTime(Math.max(0, duration - safePosition))}` : "–:––";

  return (
    <section className="fp-timeline" aria-label="Progression de la lecture">
      <div className="fp-progress-bar">
        <div className="fp-progress-track">
          <div className="fp-progress-fill" style={{ width: `${progress}%` }} />
          <div className="fp-progress-thumb" style={{ left: `${progress}%` }} />
        </div>
        <input
          className="fp-progress-input"
          type="range"
          min="0"
          max={duration || 1}
          step="1"
          value={safePosition}
          onChange={(e) => seekTo(Number(e.target.value))}
          disabled={controlsLocked || duration <= 0}
          aria-label="Position de lecture"
          aria-valuetext={`${positionLabel} sur ${durationLabel}`}
        />
      </div>
      <div className="fp-time-labels">
        <time>{positionLabel}</time>
        <time aria-label={`${durationLabel} au total`}>{remainingLabel}</time>
      </div>
    </section>
  );
}
