import { afterEach, describe, expect, it, vi } from "vitest";
import { addLibraryLike, createLibraryPlaylist, fetchHome, fetchLibrary, fetchPlaylist, fetchRadio, fetchSearch, getAudioStreamUrl, resolveAudioStream } from "./api";

describe("web api client", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    localStorage.clear();
  });

  it("fetches home catalog from API v2", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ sections: [] }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchHome()).resolves.toEqual({ sections: [] });
    expect(fetchMock).toHaveBeenCalledWith("/api/v2/catalog/home");
  });

  it("encodes search queries", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ results: [] }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await fetchSearch("damso feu de bois");
    expect(fetchMock).toHaveBeenCalledWith("/api/v2/catalog/search?q=damso%20feu%20de%20bois");
  });

  it("targets playlist details and media streams", async () => {
    const fetchMock = vi.fn(async () => new Response(JSON.stringify({ title: "Playlist" }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await fetchPlaylist("PL123");
    expect(fetchMock).toHaveBeenCalledWith("/api/v2/catalog/playlist/PL123");
    await fetchPlaylist("OLAK/with spaces");
    expect(fetchMock).toHaveBeenLastCalledWith("/api/v2/catalog/playlist/OLAK%2Fwith%20spaces");
    expect(getAudioStreamUrl("track-1")).toBe("/api/v2/media/stream/track-1");
  });

  it("resolves stream URLs and fetches radio queues", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ stream_url: "/api/v2/media/stream/track-1", cached: true }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ tracks: [{ id: "next" }], source: "youtube_music" }), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(resolveAudioStream("track-1")).resolves.toEqual({ stream_url: "/api/v2/media/stream/track-1", cached: true });
    await expect(fetchRadio({ id: "track-1", title: "Song", artist: "Artist" })).resolves.toEqual({ tracks: [{ id: "next" }], source: "youtube_music" });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v2/media/resolve/track-1", expect.objectContaining({ signal: expect.any(AbortSignal) }));
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v2/catalog/radio?track_id=track-1&title=Song&artist=Artist", { signal: undefined });
  });

  it("throws when an API request fails", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("nope", { status: 503 })));

    await expect(fetchHome()).rejects.toThrow("Failed to fetch home catalog");
  });

  it("uses authenticated library endpoints for likes and playlists", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ likes: [], playlists: [], provider: { connected: false } }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 1, name: "Road trip" }), { status: 201 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ id: 2 }), { status: 201 }));
    vi.stubGlobal("fetch", fetchMock);

    await expect(fetchLibrary()).resolves.toEqual({ likes: [], playlists: [], provider: { connected: false } });
    await expect(createLibraryPlaylist("Road trip")).resolves.toEqual({ id: 1, name: "Road trip" });
    await expect(addLibraryLike({ id: "track-1", title: "Song", artist: "Artist", artwork: "https://example.com/a.jpg", duration: 24 })).resolves.toEqual({ id: 2 });

    expect(fetchMock).toHaveBeenNthCalledWith(1, "/api/v2/library", expect.objectContaining({ credentials: "include" }));
    expect(fetchMock).toHaveBeenNthCalledWith(2, "/api/v2/library/playlists", expect.objectContaining({ method: "POST", credentials: "include" }));
    expect(fetchMock).toHaveBeenNthCalledWith(3, "/api/v2/library/likes", expect.objectContaining({ method: "POST", credentials: "include" }));
  });
});
