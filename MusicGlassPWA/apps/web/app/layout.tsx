import type { Metadata, Viewport } from "next";
import { Inter } from "next/font/google";
import "./appica.css";
import "../styles/tokens.css";
import "../styles/base.css";
import "../styles/shell.css";
import "../styles/content.css";
import "../styles/sessions.css";
import "../styles/settings.css";
import "../styles/player.css";
import "../styles/full-player.css";
import "../styles/queue.css";
import "../styles/details.css";
import "../styles/responsive.css";
import "../styles/mobile.css";
import { AppProviders } from "@/components/app-providers";
import { AppShell } from "@/components/app-shell";

const inter = Inter({ subsets: ["latin"], variable: "--font-inter", display: "swap" });

export const metadata: Metadata = {
  title: { default: "MusicGlass", template: "%s · MusicGlass" },
  description: "Votre musique, partout, ensemble.",
  applicationName: "MusicGlass",
  appleWebApp: { capable: true, statusBarStyle: "default", title: "MusicGlass" },
  icons: { apple: [{ url: "/icons/icon-192.png", sizes: "192x192", type: "image/png" }] },
};

export const viewport: Viewport = { width: "device-width", initialScale: 1, viewportFit: "cover", themeColor: "#ffffff" };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr" className={inter.variable} suppressHydrationWarning>
      <body>
        <AppProviders>
          <AppShell>{children}</AppShell>
        </AppProviders>
      </body>
    </html>
  );
}
