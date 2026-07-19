export const INSTALL_DISMISS_KEY = "musicglass-install-dismissed-at";
export const INSTALL_DISMISS_COOLDOWN_MS = 14 * 24 * 60 * 60 * 1000;

export type InstallChoice = {
  outcome: "accepted" | "dismissed";
  platform?: string;
};

export interface BeforeInstallPromptEvent extends Event {
  readonly platforms?: string[];
  readonly userChoice?: Promise<InstallChoice>;
  prompt: () => Promise<InstallChoice>;
}

export function isStandalone(displayModeMatches: boolean, navigatorStandalone?: boolean) {
  return displayModeMatches || navigatorStandalone === true;
}

export function supportsIOSInstallFallback(navigatorStandalone: unknown, maxTouchPoints: number) {
  return typeof navigatorStandalone === "boolean" && maxTouchPoints > 0;
}

export function readInstallDismissedAt(storage: Pick<Storage, "getItem">): number | null {
  try {
    const value = Number(storage.getItem(INSTALL_DISMISS_KEY));
    return Number.isFinite(value) && value > 0 ? value : null;
  } catch {
    return null;
  }
}

export function shouldShowInstallInvitation({
  standalone,
  dismissedAt,
  now = Date.now(),
}: {
  standalone: boolean;
  dismissedAt: number | null;
  now?: number;
}) {
  return !standalone && (dismissedAt == null || now - dismissedAt >= INSTALL_DISMISS_COOLDOWN_MS);
}

export function rememberInstallDismissal(storage: Pick<Storage, "setItem">, now = Date.now()) {
  try {
    storage.setItem(INSTALL_DISMISS_KEY, String(now));
  } catch {
    // Installation remains available when private storage is unavailable.
  }
}
