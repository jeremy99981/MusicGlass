"use client";

import { Alert, AlertAction, AlertDescription, AlertIcon, AlertTitle, Button, Spinner } from "@appica/ui-react";
import { Download, Share } from "lucide-react";
import React, { useEffect, useRef, useState } from "react";
import {
  type BeforeInstallPromptEvent,
  isStandalone,
  readInstallDismissedAt,
  rememberInstallDismissal,
  shouldShowInstallInvitation,
  supportsIOSInstallFallback,
} from "@/lib/pwa-install";

type InstallMode = "native" | "ios";
type NavigatorWithStandalone = Navigator & { standalone?: boolean };

export function InstallAppPrompt() {
  const promptRef = useRef<BeforeInstallPromptEvent | null>(null);
  const [mode, setMode] = useState<InstallMode | null>(null);
  const [installing, setInstalling] = useState(false);

  useEffect(() => {
    const iosNavigator = navigator as NavigatorWithStandalone;
    const standalone = isStandalone(
      window.matchMedia("(display-mode: standalone)").matches,
      iosNavigator.standalone,
    );
    const canInvite = shouldShowInstallInvitation({
      standalone,
      dismissedAt: readInstallDismissedAt(window.localStorage),
    });
    if (!canInvite) return;

    const onBeforeInstallPrompt = (event: Event) => {
      event.preventDefault();
      promptRef.current = event as BeforeInstallPromptEvent;
      setMode("native");
    };
    const onInstalled = () => {
      promptRef.current = null;
      setMode(null);
    };

    window.addEventListener("beforeinstallprompt", onBeforeInstallPrompt);
    window.addEventListener("appinstalled", onInstalled);

    const iosTimer = supportsIOSInstallFallback(iosNavigator.standalone, navigator.maxTouchPoints)
      ? window.setTimeout(() => setMode((current) => current ?? "ios"), 1800)
      : null;

    return () => {
      window.removeEventListener("beforeinstallprompt", onBeforeInstallPrompt);
      window.removeEventListener("appinstalled", onInstalled);
      if (iosTimer != null) window.clearTimeout(iosTimer);
    };
  }, []);

  const dismiss = () => {
    promptRef.current = null;
    rememberInstallDismissal(window.localStorage);
    setMode(null);
  };

  const install = async () => {
    const prompt = promptRef.current;
    if (!prompt || installing) return;
    promptRef.current = null;
    setInstalling(true);
    try {
      const choice = await prompt.prompt();
      if (choice.outcome === "dismissed") rememberInstallDismissal(window.localStorage);
    } catch {
      rememberInstallDismissal(window.localStorage);
    } finally {
      setInstalling(false);
      setMode(null);
    }
  };

  if (!mode) return null;

  const ios = mode === "ios";
  const Icon = ios ? Share : Download;
  return (
    <aside
      className="pointer-events-none fixed right-4 bottom-[calc(max(8px,env(safe-area-inset-bottom))+164px)] z-480 w-[min(390px,calc(100vw-32px))] sm:right-[max(20px,env(safe-area-inset-right))] sm:bottom-[max(20px,env(safe-area-inset-bottom))]"
      aria-label="Installation de MusicGlass"
    >
      <Alert
        role="status"
        variant="success"
        dismissible
        open
        onOpenChange={(open) => { if (!open) dismiss(); }}
        closeLabel="Masquer l’invitation"
        className="pointer-events-auto translate-y-0 scale-100 overflow-hidden border-white/15 bg-[radial-gradient(circle_at_5%_0%,rgba(49,232,120,0.2),transparent_44%),linear-gradient(145deg,rgba(18,28,22,0.97),rgba(7,12,9,0.98))] p-4 pe-12 text-[#fff7f9] opacity-100 shadow-[0_24px_70px_rgba(0,0,0,0.48)] transition duration-300 starting:translate-y-3 starting:scale-[0.98] starting:opacity-0 motion-reduce:transition-none [&_[data-slot=alert-close]]:absolute [&_[data-slot=alert-close]]:top-2.5 [&_[data-slot=alert-close]]:right-2.5 [&_[data-slot=alert-close]]:m-0 [&_[data-slot=alert-close]]:text-white/60"
      >
        <AlertIcon className="me-3 grid size-10 place-items-center rounded-xl bg-[linear-gradient(135deg,#91f5b3,#31e878)] text-[#171117]">
          <Icon size={20} />
        </AlertIcon>
        <AlertTitle className="text-[15px] font-bold tracking-[-0.01em] text-[#fff7f9]">
          {ios ? "Installer sur cet appareil" : "Emportez MusicGlass"}
        </AlertTitle>
        <AlertDescription className="mt-1 text-[13px] leading-[1.42] text-[#fff7f9]/68">
          {ios
            ? "Touchez Partager, puis Sur l’écran d’accueil."
            : "Accès rapide, plein écran et interface disponible hors connexion."}
        </AlertDescription>
        {!ios && (
          <AlertAction className="mt-3">
            <Button type="button" variant="light" size="sm" disabled={installing} onClick={() => void install()}>
              {installing && <Spinner currentColor className="text-base" aria-label="Installation en cours" />}
              {installing ? "Installation…" : "Installer"}
            </Button>
          </AlertAction>
        )}
      </Alert>
    </aside>
  );
}
