/* eslint-disable @typescript-eslint/no-explicit-any */

import { cleanTrackArtist, inferTrackArtist } from "./catalog";

// ── Types ────────────────────────────────────────────────────────────────────

// `Track` est défini dans ./catalog (source unique) et ré-exporté ici pour les
// consommateurs qui importent depuis ce module.
export type { Track } from "./catalog";

export type HomeItem = {
  id: string;
  title: string;
  subtitle: string;
  artwork: string;
  type: "track" | "playlist" | "album" | "artist";
  duration?: number;
};

export type HomeSection = {
  title: string;
  items: HomeItem[];
};

export type Collection = {
  title: string;
  subtitle: string;
  color: string;
  id: string;
};

// ── Helpers ──────────────────────────────────────────────────────────────────
/**
 * Safely extract text from YouTube's nested text runs.
 */
export function extractText(obj: any): string {
  if (!obj) return "";
  if (obj.runs && Array.isArray(obj.runs)) {
    return obj.runs.map((r: any) => r.text).join("");
  }
  if (obj.simpleText) return obj.simpleText;
  return "";
}

function findObjectsNamed(root: any, name: string): any[] {
  const results: any[] = [];
  function search(obj: any) {
    if (typeof obj !== "object" || obj === null) return;
    if (Array.isArray(obj)) {
      for (const item of obj) search(item);
      return;
    }
    for (const key of Object.keys(obj)) {
      if (key === name) {
        results.push(obj[key]);
      } else {
        search(obj[key]);
      }
    }
  }
  search(root);
  return results;
}



type ArtworkContext = "track" | "video" | "collection" | "artist";

type ThumbnailCandidate = {
  url?: unknown;
  width?: unknown;
  height?: unknown;
};

type RankedThumbnail = ThumbnailCandidate & { sourcePriority: number };

function positiveDimension(value: unknown): number | undefined {
  const dimension = typeof value === "number" ? value : Number(value);
  return Number.isFinite(dimension) && dimension > 0 ? dimension : undefined;
}

function dimensionsFromURL(url: string): { width?: number; height?: number } {
  const sizedCrop = url.match(/=w(\d+)-h(\d+)/);
  if (sizedCrop) return { width: Number(sizedCrop[1]), height: Number(sizedCrop[2]) };

  const videoSize = url.match(/\/(maxresdefault|hq720|sddefault|hqdefault|mqdefault|default)\.jpg(?:$|[?#])/);
  if (!videoSize) return {};
  const sizes: Record<string, [number, number]> = {
    maxresdefault: [1280, 720],
    hq720: [1280, 720],
    sddefault: [640, 480],
    hqdefault: [480, 360],
    mqdefault: [320, 180],
    default: [120, 90],
  };
  const [width, height] = sizes[videoSize[1]];
  return { width, height };
}

function normalizeThumbnailURL(value: unknown): string {
  if (typeof value !== "string" || !value) return "";
  return value.startsWith("//") ? `https:${value}` : value;
}

function thumbnailScore(candidate: RankedThumbnail, context: ArtworkContext): number {
  const url = normalizeThumbnailURL(candidate.url);
  if (!url) return Number.NEGATIVE_INFINITY;

  const inferred = dimensionsFromURL(url);
  const width = positiveDimension(candidate.width) ?? inferred.width;
  const height = positiveDimension(candidate.height) ?? inferred.height;
  const videoThumbnail = /(?:^|\.)ytimg\.com\/vi(?:_webp)?\//.test(url);
  let score = candidate.sourcePriority * 100;

  if (width && height) {
    const squareDelta = Math.abs(width / height - 1);
    if (squareDelta <= 0.08) score += 1_000_000;
    else if (squareDelta <= 0.2) score += 500_000;
    else score -= 300_000;
    score += Math.min(width, height, 2000);
  } else if (candidate.sourcePriority >= 300) {
    // A Music thumbnail with missing dimensions is still preferable to a known video frame.
    score += 350_000;
  }

  if (videoThumbnail && context !== "video") score -= 800_000;
  return score;
}

function selectThumbnail(candidates: RankedThumbnail[], context: ArtworkContext): string {
  const ranked = candidates
    .filter((candidate) => normalizeThumbnailURL(candidate.url))
    .sort((left, right) => thumbnailScore(right, context) - thumbnailScore(left, context));
  return normalizeThumbnailURL(ranked[0]?.url);
}

function candidatesFrom(value: unknown, sourcePriority: number): RankedThumbnail[] {
  return Array.isArray(value)
    ? value.map((candidate) => ({ ...(candidate as ThumbnailCandidate), sourcePriority }))
    : [];
}

function directCandidate(value: unknown, sourcePriority: number): RankedThumbnail[] {
  if (typeof value === "string") return [{ url: value, sourcePriority }];
  if (value && typeof value === "object" && "url" in value) {
    return [{ ...(value as ThumbnailCandidate), sourcePriority }];
  }
  return [];
}

function extractCanonicalThumbnail(item: any, context: ArtworkContext, fallback = ""): string {
  return selectThumbnail([
    ...candidatesFrom(item?.artworks, 350),
    ...candidatesFrom(item?.thumbnails, 300),
    ...directCandidate(item?.artwork, 320),
    ...directCandidate(item?.cover_url, 300),
    ...directCandidate(item?.thumbnail, 250),
    ...directCandidate(fallback, 10),
  ], context);
}

/** Selects official square Music artwork before generic video thumbnails. */
function extractThumbnail(renderer: any, context: ArtworkContext): string {
  return selectThumbnail([
    ...candidatesFrom(renderer?.thumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails, 400),
    ...candidatesFrom(renderer?.thumbnailRenderer?.musicThumbnailRenderer?.thumbnail?.thumbnails, 400),
    ...candidatesFrom(renderer?.thumbnail?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails, 380),
    ...candidatesFrom(renderer?.thumbnailRenderer?.croppedSquareThumbnailRenderer?.thumbnail?.thumbnails, 380),
    ...candidatesFrom(renderer?.foregroundThumbnail?.musicThumbnailRenderer?.thumbnail?.thumbnails, 360),
    ...candidatesFrom(renderer?.thumbnail?.thumbnails, 100),
    ...candidatesFrom(renderer?.thumbnailRenderer?.thumbnail?.thumbnails, 100),
  ], context);
}

export function highResolutionArtwork(url: string): string {
  if (!url || /(?:^|\.)ytimg\.com\/vi(?:_webp)?\//.test(url)) return url;
  return url.replace(/=w\d+-h\d+[^/?#]*$/, "=w1200-h1200-l90-rj");
}

/**
 * Generate fallback thumbnails from a video ID (ytimg.com).
 */
function fallbackThumbnail(videoId: string): string {
  if (!videoId || videoId.length !== 11) return "";
  return `https://i.ytimg.com/vi/${videoId}/hq720.jpg`;
}

function parseDurationText(value: string): number {
  const match = value.match(/(?:^|[•·\s])((?:\d{1,2}:)?\d{1,2}:\d{2})(?:\s|$)/);
  if (!match) return 0;
  const parts = match[1].split(":").map((part) => Number.parseInt(part, 10));
  if (parts.some((part) => Number.isNaN(part))) return 0;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return parts[0] * 60 + parts[1];
}

function cleanTrackSubtitle(value: string): string {
  const parts = value.split("•").map((part) => part.trim()).filter(Boolean);
  const candidate = /^(titre|song|vidéo|video)$/i.test(parts[0] || "") ? parts[1] || "" : parts[0] || "";
  if (!candidate || parseDurationText(candidate) > 0 || /\b(vues?|views?)\b/i.test(candidate)) return "";
  return candidate;
}

// ── Parsers ──────────────────────────────────────────────────────────────────

/**
 * Determine the item type based on its ID or browse endpoint.
 */
function classifyItem(renderer: any, id: string): HomeItem["type"] {
  // Check browse endpoint first
  const browseEndpoint = renderer?.navigationEndpoint?.browseEndpoint;
  if (browseEndpoint) {
    const browseId = browseEndpoint.browseId || "";
    const pageType = browseEndpoint?.browseEndpointContextSupportedConfigs
      ?.browseEndpointContextMusicConfig?.pageType || "";

    if (pageType.includes("ARTIST")) return "artist";
    if (pageType.includes("ALBUM")) return "album";
    if (pageType.includes("PLAYLIST") || browseId.startsWith("VL") || browseId.startsWith("RD")) return "playlist";
  }

  // Classify by ID prefix
  if (id.startsWith("PL") || id.startsWith("RD") || id.startsWith("VL") || id.startsWith("OLAK")) return "playlist";
  if (id.startsWith("MPREb_")) return "album";
  if (id.startsWith("UC") || id.startsWith("MPLA")) return "artist";

  return "track";
}

export function parseHome(data: any): { sections: HomeSection[] } {
  const sections: HomeSection[] = [];
  const carousels = findObjectsNamed(data, "musicCarouselShelfRenderer");
  const shelves = findObjectsNamed(data, "musicShelfRenderer");
  const grids = findObjectsNamed(data, "gridRenderer");
  const allSections = [...carousels, ...shelves, ...grids];

  for (const section of allSections) {
    let title = "Recommandations";
    if (section.header?.musicCarouselShelfBasicHeaderRenderer?.title) {
      title = extractText(section.header.musicCarouselShelfBasicHeaderRenderer.title) || title;
    } else if (section.header?.musicImmersiveCarouselShelfBasicHeaderRenderer?.title) {
      title = extractText(section.header.musicImmersiveCarouselShelfBasicHeaderRenderer.title) || title;
    } else if (section.title) {
      title = extractText(section.title) || title;
    }

    const items = section.contents || section.items || [];
    const sectionItems: HomeItem[] = [];

    for (const item of items) {
      const renderer = item.musicResponsiveListItemRenderer || item.musicTwoRowItemRenderer;
      if (!renderer) continue;

      // 1. Try to get a direct videoId (= this is a playable track)
      let videoId: string | null = null;
      videoId = renderer?.playlistItemData?.videoId || null;
      if (!videoId) {
        const watchEndpoint =
          renderer?.navigationEndpoint?.watchEndpoint ||
          renderer?.overlay?.musicItemThumbnailOverlayRenderer?.content
            ?.musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint;
        if (watchEndpoint?.videoId) videoId = watchEndpoint.videoId;
      }

      // 2. Try to get a browseId (= this is a playlist/album/artist)
      let browseId: string | null = null;
      const browseEndpoint = renderer?.navigationEndpoint?.browseEndpoint;
      if (browseEndpoint?.browseId) {
        browseId = browseEndpoint.browseId;
      }

      // Determine the actual ID and type
      const id = videoId || browseId;
      if (!id) continue;

      const itemTitle = extractText(renderer.title) ||
        extractText(renderer.flexColumns?.[0]?.musicResponsiveListItemFlexColumnRenderer?.text) ||
        "Titre inconnu";
      const rawSubtitle = extractText(renderer.subtitle) ||
        extractText(renderer.flexColumns?.[1]?.musicResponsiveListItemFlexColumnRenderer?.text) ||
        "";

      const type = videoId ? "track" : classifyItem(renderer, id);
      let artwork = extractThumbnail(renderer, type === "track" ? "track" : type === "artist" ? "artist" : "collection");
      if (!artwork && videoId) artwork = fallbackThumbnail(videoId);
      const subtitle = type === "track" ? cleanTrackArtist(cleanTrackSubtitle(rawSubtitle)) || inferTrackArtist(itemTitle) : rawSubtitle;

      // Strip "VL" prefix from playlist IDs for cleaner routing
      const cleanId = type === "playlist" && id.startsWith("VL") ? id.slice(2) : id;

      if (!sectionItems.find((existing) => existing.id === cleanId)) {
        sectionItems.push({ id: cleanId, title: itemTitle, subtitle, artwork, type, duration: parseDurationText(rawSubtitle) });
      }
    }

    if (sectionItems.length > 0) {
      const existing = sections.find((s) => s.title === title);
      if (existing) {
        existing.items.push(
          ...sectionItems.filter((newItem) => !existing.items.find((e) => e.id === newItem.id))
        );
      } else {
        sections.push({ title, items: sectionItems });
      }
    }
  }

  return { sections };
}

export type SearchItem = {
  id: string;
  title: string;
  artist: string; // Name of the artist (or channel)
  type: "track" | "video" | "album" | "artist" | "playlist" | "episode" | "unknown";
  artwork: string;
  duration?: number;
  /** Le backend n'a pas encore résolu la pochette carrée: à résoudre à la demande. */
  artworkPending?: boolean;
};

function typedArtistFromRenderer(renderer: any): string {
  for (const runs of findObjectsNamed(renderer, "runs")) {
    if (!Array.isArray(runs)) continue;
    for (const run of runs) {
      const pageType = run?.navigationEndpoint?.browseEndpoint
        ?.browseEndpointContextSupportedConfigs?.browseEndpointContextMusicConfig?.pageType;
      if (pageType === "MUSIC_PAGE_TYPE_ARTIST") {
        const artist = cleanTrackArtist(String(run?.text || ""));
        if (artist) return artist;
      }
    }
  }
  return "";
}

function comparable(value: string): string {
  return value.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLocaleLowerCase("fr").trim();
}

export function parseSearch(data: any, searchQuery = ""): SearchItem[] {
  const items: SearchItem[] = [];
  const listRenderers = findObjectsNamed(data, "musicResponsiveListItemRenderer");
  const cardRenderers = findObjectsNamed(data, "musicCardShelfRenderer");
  const renderers = [...cardRenderers, ...listRenderers];

  for (const renderer of renderers) {
    let itemId =
      renderer?.playlistItemData?.videoId || renderer?.navigationItemData?.videoId;

    if (!itemId) {
      const watchEndpoint =
        renderer?.flexColumns?.[0]?.musicResponsiveListItemFlexColumnRenderer?.text
          ?.runs?.[0]?.navigationEndpoint?.watchEndpoint ||
        renderer?.overlay?.musicItemThumbnailOverlayRenderer?.content
          ?.musicPlayButtonRenderer?.playNavigationEndpoint?.watchEndpoint;
      if (watchEndpoint?.videoId) itemId = watchEndpoint.videoId;
    }

    if (!itemId) {
      // It might be an artist, album, or playlist which uses browseEndpoint
      const browseEndpoint =
        renderer?.flexColumns?.[0]?.musicResponsiveListItemFlexColumnRenderer?.text
          ?.runs?.[0]?.navigationEndpoint?.browseEndpoint ||
        renderer?.navigationEndpoint?.browseEndpoint ||
        renderer?.onTap?.browseEndpoint ||
        renderer?.title?.runs?.[0]?.navigationEndpoint?.browseEndpoint;
      if (browseEndpoint?.browseId) itemId = browseEndpoint.browseId;
    }

    if (!itemId) continue;

    const title =
      extractText(
        renderer.flexColumns?.[0]?.musicResponsiveListItemFlexColumnRenderer?.text
      ) ||
      extractText(renderer.title) ||
      "Titre inconnu";
      
    const rawSubtitle =
      extractText(
        renderer.flexColumns?.[1]?.musicResponsiveListItemFlexColumnRenderer?.text
      ) ||
      extractText(renderer.subtitle) ||
      "";

    let type: SearchItem["type"] = "unknown";
    let artist = "";

    const parts = rawSubtitle.split("•").map((p: string) => p.trim());
    const typeIndicator = parts[0]?.toLowerCase() || "";
    const typedArtist = typedArtistFromRenderer(renderer);

    // User profiles and channels are not playable music results.
    if (typeIndicator === "profil" || typeIndicator === "profile") continue;

    if (typeIndicator === "titre" || typeIndicator === "song") {
      type = "track";
      artist = typedArtist || cleanTrackSubtitle(rawSubtitle);
    } else if (typeIndicator === "vidéo" || typeIndicator === "video") {
      type = "video";
      artist = typedArtist || cleanTrackSubtitle(rawSubtitle);
    } else if (typeIndicator === "album" || typeIndicator === "single" || typeIndicator === "ep") {
      type = "album";
      artist = typedArtist || parts[1] || "";
    } else if (typeIndicator === "artiste" || typeIndicator === "artist") {
      type = "artist";
      artist = title; // For artists, the title is the artist name
    } else if (typeIndicator === "playlist") {
      type = "playlist";
      artist = parts[1] || "";
    } else if (typeIndicator === "épisode" || typeIndicator === "episode" || typeIndicator === "podcast") {
      type = "episode";
      artist = parts[1] || "";
    } else {
      // Fallback if no clear indicator
      if (parts.length >= 2 && !rawSubtitle.includes("abonnés") && !rawSubtitle.includes("vues")) {
        type = "track";
        artist = typedArtist || parts[0];
      } else {
        type = classifyItem(renderer, itemId);
        artist = type === "artist" ? title : typedArtist || rawSubtitle;
      }
    }

    let artwork = extractThumbnail(renderer, type === "video" ? "video" : type === "track" ? "track" : type === "artist" ? "artist" : "collection");
    if (!artwork) artwork = fallbackThumbnail(itemId);

    if (!items.find((i) => i.id === itemId)) {
      items.push({
        id: itemId,
        title: title,
        artist: cleanTrackArtist(artist) || inferTrackArtist(title),
        type: type,
        artwork: artwork,
        duration: parseDurationText(rawSubtitle),
      });
    }
  }

  const normalizedQuery = comparable(searchQuery);
  const matchingArtist = items.find((item) => item.type === "artist" && (
    comparable(item.title) === normalizedQuery ||
    (normalizedQuery.length > 2 && normalizedQuery.includes(comparable(item.title)))
  ));

  return items.map((item) => {
    if ((item.type === "track" || item.type === "video") && !item.artist && matchingArtist) {
      return { ...item, artist: matchingArtist.title };
    }
    return item;
  });
}

export function parsePlaylist(data: any): {
  title: string;
  subtitle: string;
  artist: string;
  artwork: string;
  tracks: SearchItem[];
} {
  const canonicalDuration = (item: any) => {
    const milliseconds = Number(item?.duration_ms);
    if (Number.isFinite(milliseconds) && milliseconds > 0) return milliseconds / 1000;
    if (typeof item?.duration === "string" && item.duration.includes(":")) return parseDurationText(item.duration);
    const seconds = Number(item?.duration ?? item?.duration_seconds);
    return Number.isFinite(seconds) && seconds > 0 ? seconds : 0;
  };
  const canonicalTracks = Array.isArray(data?.tracks) ? data.tracks : Array.isArray(data?.items) ? data.items : null;
  if (canonicalTracks) {
    const tracks = canonicalTracks
      .map((item: any): SearchItem | null => {
        const id = String(item?.id || item?.videoId || item?.track_id || "");
        if (!id) return null;
        const canonicalArtists = Array.isArray(item?.artists)
          ? item.artists
              .map((artist: any) => typeof artist === "string" ? artist : artist?.name)
              .filter(Boolean)
              .join(" · ")
          : "";
        const itemTitle = String(item?.title || item?.name || "Titre inconnu");
        return {
          id,
          title: itemTitle,
          artist: cleanTrackArtist(String(item?.artist || item?.subtitle || canonicalArtists)) || inferTrackArtist(itemTitle),
          type: item?.type === "video" ? "video" : "track",
          artwork: extractCanonicalThumbnail(item, item?.type === "video" ? "video" : "track"),
          duration: canonicalDuration(item),
          artworkPending: Boolean(item?.artwork_pending),
        };
      })
      .filter(Boolean) as SearchItem[];

    return {
      title: String(data?.title || data?.name || "Playlist"),
      subtitle: String(data?.subtitle || data?.description || data?.year || ""),
      artist: String(data?.artist || data?.owner || ""),
      artwork: extractCanonicalThumbnail(data, "collection", tracks[0]?.artwork || ""),
      tracks,
    };
  }

  let title = "Playlist";
  let subtitle = "";
  let artist = "";
  let artwork = "";

  // Try multiple header renderer types (matching Flutter's _headerThumbnails logic)
  const headerTypes = [
    "musicImmersiveHeaderRenderer",
    "musicResponsiveHeaderRenderer",
    "musicDetailHeaderRenderer",
    "musicEditablePlaylistDetailHeaderRenderer",
    "musicVisualHeaderRenderer",
  ];

  for (const headerType of headerTypes) {
    const headers = findObjectsNamed(data, headerType);
    if (headers.length === 0) continue;
    const header = headers[0];

    title = extractText(header.title) || title;
    subtitle = extractText(header.subtitle) || subtitle;
    artist = extractText(header.straplineTextOne) || artist;

    artwork = extractThumbnail(header, "collection");

    if (title !== "Playlist" || artwork) break;
  }

  const tracks = parseSearch(data);
  return { title, subtitle, artist, artwork, tracks };
}
