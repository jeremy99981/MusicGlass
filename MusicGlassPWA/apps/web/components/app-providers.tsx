"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider } from "@appica/ui-react/providers/theme-provider";
import { ReducedMotionProvider } from "@appica/ui-react/providers/reduced-motion-provider";
import { useState, type ReactNode } from "react";
import { AudioEngine } from "./audio-engine";
import { InstallAppPrompt } from "./install-app-prompt";
import { ServiceWorkerRegistration } from "./service-worker-registration";
import { SharedSessionProvider } from "./shared-session-provider";

export function AppProviders({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => new QueryClient({ defaultOptions: { queries: { staleTime: 30_000, refetchOnWindowFocus: false } } }));
  return (
    <ThemeProvider forcedTheme="dark" enableSystem={false} storageKey="musicglass-theme">
      <ReducedMotionProvider>
        <QueryClientProvider client={queryClient}>
          <AudioEngine />
          <SharedSessionProvider />
          <ServiceWorkerRegistration />
          <InstallAppPrompt />
          {children}
        </QueryClientProvider>
      </ReducedMotionProvider>
    </ThemeProvider>
  );
}
