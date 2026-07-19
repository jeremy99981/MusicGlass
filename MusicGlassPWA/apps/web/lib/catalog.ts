export type Track = {
  id: string;
  title: string;
  artist: string;
  album: string;
  artwork: string;
  duration: number;
  accent: string;
  audioUrl?: string;
};

const INVALID_ARTIST_LABELS = new Set([
  "artiste inconnu",
  "unknown artist",
  "artiste",
  "titre",
  "track",
  "video",
  "vidéo",
  "profil",
  "profile",
  "playlist",
]);

export function cleanTrackArtist(value?: string) {
  const artist = value?.replace(/\s+/g, " ").trim() ?? "";
  return INVALID_ARTIST_LABELS.has(artist.toLocaleLowerCase("fr")) ? "" : artist;
}

export function inferTrackArtist(title?: string) {
  const match = title?.match(/^\s*([^\-–—|]{2,80})\s*[\-–—|]\s*[^\-–—|]{2,}/);
  return cleanTrackArtist(match?.[1]);
}

export function hasReliableTrackMetadata(track: Pick<Track, "id" | "title" | "artist">) {
  return Boolean(track.id.trim() && track.title.trim() && cleanTrackArtist(track.artist));
}

export function normalizeTrack(input: Partial<Track> & { id: string; title?: string; artist?: string; artwork?: string }): Track {
  const rawDuration = Number(input.duration);
  const duration = Number.isFinite(rawDuration) && rawDuration > 0 ? rawDuration : 0;
  const title = input.title?.replace(/\s+/g, " ").trim() || "Titre inconnu";
  return {
    id: input.id,
    title,
    artist: cleanTrackArtist(input.artist) || inferTrackArtist(title),
    album: input.album || "",
    artwork: input.artwork || "",
    duration,
    accent: input.accent || "#263443",
    audioUrl: input.audioUrl,
  };
}

export function uniqueTracks(tracks: Track[]) {
  const merged = new Map<string, Track>();
  for (const track of tracks) {
    if (!track.id) continue;
    const existing = merged.get(track.id);
    if (!existing) {
      merged.set(track.id, normalizeTrack(track));
      continue;
    }
    merged.set(track.id, normalizeTrack({
      ...existing,
      ...track,
      title: track.title || existing.title,
      artist: track.artist || existing.artist,
      album: track.album || existing.album,
      artwork: track.artwork || existing.artwork,
      duration: track.duration > 0 ? track.duration : existing.duration,
      audioUrl: track.audioUrl || existing.audioUrl,
    }));
  }
  return [...merged.values()];
}

export const demoTracks: Track[] = [
  { id: "outside", title: "Outside", artist: "Calvin Harris · Ellie Goulding", album: "Motion", artwork: "https://i.ytimg.com/vi/J9NQFACZYEU/maxresdefault.jpg", duration: 24, accent: "#8cb5d2", audioUrl: "/demo-preview.m4a" },
  { id: "airplanes", title: "Airplanes", artist: "B.o.B · Hayley Williams", album: "B.o.B Presents", artwork: "https://i.ytimg.com/vi/kn6-c223DUU/maxresdefault.jpg", duration: 24, accent: "#dfbd38", audioUrl: "/demo-preview.m4a" },
  { id: "feu-de-bois", title: "Feu de bois", artist: "Damso", album: "Lithopédion", artwork: "https://i.ytimg.com/vi/9PODnRarD78/maxresdefault.jpg", duration: 24, accent: "#b7c2ce", audioUrl: "/demo-preview.m4a" },
  { id: "worldwide", title: "Worldwide", artist: "Curtis Heron", album: "Midnight drive", artwork: "https://i.ytimg.com/vi/k85mRPqvMbE/maxresdefault.jpg", duration: 24, accent: "#d75151", audioUrl: "/demo-preview.m4a" },
  { id: "afterglow", title: "Afterglow", artist: "Phaeleh", album: "Fallen Light", artwork: "https://i.ytimg.com/vi/lPOTQJg6sfg/maxresdefault.jpg", duration: 24, accent: "#bda398", audioUrl: "/demo-preview.m4a" },
];

export const collections = [
  { title: "Vibrations nocturnes", subtitle: "32 titres", color: "linear-gradient(145deg,#6e44ff,#f054a2)" },
  { title: "Tout doux", subtitle: "Pour ralentir", color: "linear-gradient(145deg,#263443,#8bb7aa)" },
  { title: "Aesthetics by Leon", subtitle: "262 titres", color: "linear-gradient(145deg,#e5b9c6,#8274ff)" },
  { title: "Épisodes pour plus tard", subtitle: "Playlist", color: "linear-gradient(145deg,#f2a65a,#ef6f6c)" },
];
