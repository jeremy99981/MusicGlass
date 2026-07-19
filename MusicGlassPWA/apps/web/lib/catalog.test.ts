import { describe, expect, it } from "vitest";
import { cleanTrackArtist, hasReliableTrackMetadata, inferTrackArtist, normalizeTrack } from "./catalog";

describe("catalog track metadata", () => {
  it.each(["Artiste inconnu", "Titre", "Vidéo", "Profil", "Playlist"])("rejects the generic artist label %s", (artist) => {
    expect(cleanTrackArtist(artist)).toBe("");
  });

  it("infers the artist from conventional video titles", () => {
    expect(inferTrackArtist("Ziak - FENG SHUI")).toBe("Ziak");
    expect(normalizeTrack({ id: "track", title: "Ziak - FENG SHUI", artist: "Vidéo" }).artist).toBe("Ziak");
  });

  it("only accepts recommendations with an identified artist", () => {
    expect(hasReliableTrackMetadata({ id: "track", title: "FENG SHUI", artist: "Ziak" })).toBe(true);
    expect(hasReliableTrackMetadata({ id: "profile", title: "Ziak", artist: "Profil" })).toBe(false);
  });
});
