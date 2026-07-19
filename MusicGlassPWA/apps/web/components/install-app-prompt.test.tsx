import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import React from "react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { InstallAppPrompt } from "./install-app-prompt";

function setNavigatorInstallState(standalone: boolean | undefined, maxTouchPoints: number) {
  Object.defineProperty(navigator, "standalone", { value: standalone, configurable: true });
  Object.defineProperty(navigator, "maxTouchPoints", { value: maxTouchPoints, configurable: true });
}

describe("InstallAppPrompt", () => {
  beforeEach(() => {
    localStorage.clear();
    setNavigatorInstallState(undefined, 0);
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: vi.fn(() => ({ matches: false, addEventListener: vi.fn(), removeEventListener: vi.fn() })),
    });
  });

  afterEach(() => {
    cleanup();
    vi.useRealTimers();
  });

  it("offers and consumes the browser install prompt from a user action", async () => {
    const prompt = vi.fn().mockResolvedValue({ outcome: "accepted", platform: "web" });
    render(<InstallAppPrompt />);

    const event = new Event("beforeinstallprompt", { cancelable: true });
    Object.defineProperty(event, "prompt", { value: prompt });
    fireEvent(window, event);

    expect(event.defaultPrevented).toBe(true);
    fireEvent.click(screen.getByRole("button", { name: "Installer" }));

    await waitFor(() => expect(prompt).toHaveBeenCalledOnce());
    await waitFor(() => expect(screen.queryByLabelText("Installation de MusicGlass")).not.toBeInTheDocument());
  });

  it("shows manual iOS instructions after a short non-blocking delay", () => {
    vi.useFakeTimers();
    setNavigatorInstallState(false, 5);
    render(<InstallAppPrompt />);

    expect(screen.queryByText("Installer sur cet appareil")).not.toBeInTheDocument();
    act(() => vi.advanceTimersByTime(1800));

    expect(screen.getByText("Installer sur cet appareil")).toBeInTheDocument();
    expect(screen.getByText(/Sur l’écran d’accueil/)).toBeInTheDocument();
  });

  it("never invites an app already running standalone", () => {
    Object.defineProperty(window, "matchMedia", {
      configurable: true,
      value: vi.fn(() => ({ matches: true, addEventListener: vi.fn(), removeEventListener: vi.fn() })),
    });
    render(<InstallAppPrompt />);

    const event = new Event("beforeinstallprompt", { cancelable: true });
    Object.defineProperty(event, "prompt", { value: vi.fn() });
    fireEvent(window, event);

    expect(event.defaultPrevented).toBe(false);
    expect(screen.queryByLabelText("Installation de MusicGlass")).not.toBeInTheDocument();
  });
});
