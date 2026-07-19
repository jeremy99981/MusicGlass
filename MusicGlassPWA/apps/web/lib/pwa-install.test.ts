import { describe, expect, it, vi } from "vitest";
import {
  INSTALL_DISMISS_COOLDOWN_MS,
  INSTALL_DISMISS_KEY,
  isStandalone,
  readInstallDismissedAt,
  rememberInstallDismissal,
  shouldShowInstallInvitation,
  supportsIOSInstallFallback,
} from "./pwa-install";

describe("PWA installation policy", () => {
  it("recognizes standard and iOS standalone modes", () => {
    expect(isStandalone(true, false)).toBe(true);
    expect(isStandalone(false, true)).toBe(true);
    expect(isStandalone(false, false)).toBe(false);
  });

  it("only enables the manual fallback on touch Apple web-app environments", () => {
    expect(supportsIOSInstallFallback(false, 5)).toBe(true);
    expect(supportsIOSInstallFallback(undefined, 5)).toBe(false);
    expect(supportsIOSInstallFallback(false, 0)).toBe(false);
  });

  it("respects the dismissal cooldown", () => {
    const now = 10_000_000_000;
    expect(shouldShowInstallInvitation({ standalone: true, dismissedAt: null, now })).toBe(false);
    expect(shouldShowInstallInvitation({ standalone: false, dismissedAt: now - 1000, now })).toBe(false);
    expect(shouldShowInstallInvitation({ standalone: false, dismissedAt: now - INSTALL_DISMISS_COOLDOWN_MS, now })).toBe(true);
  });

  it("reads and writes dismissal storage defensively", () => {
    const storage = { getItem: vi.fn(() => "1234"), setItem: vi.fn() };
    expect(readInstallDismissedAt(storage)).toBe(1234);

    rememberInstallDismissal(storage, 5678);
    expect(storage.setItem).toHaveBeenCalledWith(INSTALL_DISMISS_KEY, "5678");

    expect(readInstallDismissedAt({ getItem: () => { throw new Error("blocked"); } })).toBeNull();
    expect(() => rememberInstallDismissal({ setItem: () => { throw new Error("blocked"); } })).not.toThrow();
  });
});
