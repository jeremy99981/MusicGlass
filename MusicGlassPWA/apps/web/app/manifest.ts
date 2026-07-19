import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "MusicGlass",
    short_name: "MusicGlass",
    description: "Votre musique, partout, ensemble.",
    id: "/",
    lang: "fr",
    dir: "ltr",
    start_url: "/",
    scope: "/",
    display: "standalone",
    background_color: "#080a09",
    theme_color: "#080a09",
    orientation: "any",
    categories: ["music", "entertainment"],
    icons: [
      { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png", purpose: "any" },
      { src: "/icons/icon-512.png", sizes: "512x512", type: "image/png", purpose: "any" },
      { src: "/icons/icon-maskable-512.png", sizes: "512x512", type: "image/png", purpose: "maskable" },
    ],
    shortcuts: [
      { name: "Accueil", short_name: "Accueil", description: "Ouvrir l’accueil MusicGlass", url: "/", icons: [{ src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" }] },
      { name: "Recherche", short_name: "Recherche", description: "Rechercher un titre, un album ou un artiste", url: "/search", icons: [{ src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" }] },
      { name: "Bibliothèque", short_name: "Bibliothèque", description: "Ouvrir votre bibliothèque", url: "/library", icons: [{ src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" }] },
    ],
  };
}
