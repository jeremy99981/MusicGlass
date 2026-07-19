import { describe, it, expect } from "vitest";
import { highResolutionArtwork, parseHome, parsePlaylist, parseSearch } from "./youtube";

describe("YouTube Parser", () => {
  it("should parse home catalog data correctly", () => {
    const mockData = {
      contents: [
        {
          musicCarouselShelfRenderer: {
            header: {
              musicCarouselShelfBasicHeaderRenderer: {
                title: { runs: [{ text: "Pour vous" }] },
              },
            },
            contents: [
              {
                musicResponsiveListItemRenderer: {
                  playlistItemData: { videoId: "test-id-1" },
                  title: { runs: [{ text: "Song 1" }] },
                  subtitle: { runs: [{ text: "Artist 1" }] },
                },
              },
            ],
          },
        },
      ],
    };

    const result = parseHome(mockData);
    expect(result.sections.length).toBe(1);
    expect(result.sections[0].title).toBe("Pour vous");

    expect(result.sections[0].items.length).toBe(1);
    expect(result.sections[0].items[0].id).toBe("test-id-1");
    expect(result.sections[0].items[0].title).toBe("Song 1");
    expect(result.sections[0].items[0].subtitle).toBe("Artist 1");
    expect(result.sections[0].items[0].type).toBe("track");
  });

  it("should parse search data correctly", () => {
    const mockSearchData = {
      contents: [
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "search-id-1" },
            flexColumns: [
              {
                musicResponsiveListItemFlexColumnRenderer: {
                  text: { runs: [{ text: "Search Song" }] }
                }
              },
              {
                musicResponsiveListItemFlexColumnRenderer: {
                  text: { runs: [{ text: "Search Artist" }] }
                }
              }
            ]
          }
        }
      ]
    };

    const result = parseSearch(mockSearchData);
    expect(result.length).toBe(1);
    expect(result[0].id).toBe("search-id-1");
    expect(result[0].title).toBe("Search Song");
    expect(result[0].artist).toBe("Search Artist");
  });

  it("extracts durations from YouTube Music subtitles", () => {
    const mockSearchData = {
      contents: [
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "duration-id-1" },
            flexColumns: [
              {
                musicResponsiveListItemFlexColumnRenderer: {
                  text: { runs: [{ text: "Timed Song" }] },
                },
              },
              {
                musicResponsiveListItemFlexColumnRenderer: {
                  text: { runs: [{ text: "Titre" }, { text: " • " }, { text: "Artist" }, { text: " • " }, { text: "3:42" }] },
                },
              },
            ],
          },
        },
      ],
    };

    const result = parseSearch(mockSearchData);
    expect(result[0].duration).toBe(222);
    expect(result[0].artist).toBe("Artist");
  });

  it("uses an exact artist result for songs whose compact metadata omits the artist", () => {
    const artistEndpoint = {
      browseEndpoint: {
        browseId: "artist-ziak",
        browseEndpointContextSupportedConfigs: {
          browseEndpointContextMusicConfig: { pageType: "MUSIC_PAGE_TYPE_ARTIST" },
        },
      },
    };
    const result = parseSearch({
      contents: [
        {
          musicResponsiveListItemRenderer: {
            navigationEndpoint: artistEndpoint,
            flexColumns: [
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Ziak", navigationEndpoint: artistEndpoint }] } } },
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Artiste" }] } } },
            ],
          },
        },
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "DST7NfSvRlk" },
            flexColumns: [
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "FENG SHUI" }] } } },
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Titre" }, { text: " • " }, { text: "2:41" }] } } },
            ],
          },
        },
      ],
    }, "Ziak");

    expect(result.find((item) => item.id === "DST7NfSvRlk")?.artist).toBe("Ziak");
  });

  it("drops user profiles and keeps missing metadata free of generic artist labels", () => {
    const result = parseSearch({
      contents: [
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "profile-id" },
            flexColumns: [
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "ziak" }] } } },
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Profil" }, { text: " • " }, { text: "@profile" }] } } },
            ],
          },
        },
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "song-id" },
            flexColumns: [
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Song" }] } } },
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Titre" }, { text: " • " }] } } },
            ],
          },
        },
      ],
    });

    expect(result.map((item) => item.id)).toEqual(["song-id"]);
    expect(result[0].artist).toBe("");
  });

  it("removes view counts and durations from artist labels", () => {
    const data = {
      contents: [{
        musicCarouselShelfRenderer: {
          contents: [{
            musicResponsiveListItemRenderer: {
              playlistItemData: { videoId: "video-id-1" },
              title: { runs: [{ text: "Basique" }] },
              subtitle: { runs: [{ text: "Orelsan" }, { text: " • " }, { text: "118 M de vues" }, { text: " • " }, { text: "2:14" }] },
            },
          }],
        },
      }],
    };

    expect(parseHome(data).sections[0].items[0].subtitle).toBe("Orelsan");
    expect(parseHome(data).sections[0].items[0].duration).toBe(134);
  });

  it("normalizes canonical playlist durations", () => {
    const result = parsePlaylist({
      title: "Durations",
      tracks: [
        { id: "seconds", title: "Seconds", duration_seconds: 134 },
        { id: "milliseconds", title: "Milliseconds", duration_ms: 134048 },
        { id: "clock", title: "Clock", duration: "2:14" },
      ],
    });
    expect(result.tracks.map((track) => track.duration)).toEqual([134, 134.048, 134]);
  });

  it("ranks canonical artwork arrays instead of taking their first entry", () => {
    const result = parsePlaylist({
      title: "Canonical",
      tracks: [{
        id: "abcdefghijk",
        title: "Song",
        artwork: "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg",
        thumbnails: [
          { url: "https://lh3.googleusercontent.com/cover=w60-h60-l90-rj", width: 60, height: 60 },
          { url: "https://lh3.googleusercontent.com/cover=w800-h800-l90-rj", width: 800, height: 800 },
        ],
      }],
    });

    expect(result.tracks[0].artwork).toBe("https://lh3.googleusercontent.com/cover=w800-h800-l90-rj");
  });

  it("keeps independent track artworks inside playlists", () => {
    const mockPlaylistData = {
      header: {
        musicDetailHeaderRenderer: {
          title: { runs: [{ text: "Top playlist" }] },
          thumbnail: {
            musicThumbnailRenderer: {
              thumbnail: { thumbnails: [{ url: "https://example.com/playlist.jpg", width: 300, height: 300 }] },
            },
          },
        },
      },
      contents: [
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "track-a-123" },
            flexColumns: [
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Track A" }] } } },
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Titre" }, { text: " • " }, { text: "Artist A" }] } } },
            ],
            thumbnail: {
              musicThumbnailRenderer: {
                thumbnail: { thumbnails: [{ url: "https://example.com/track-a.jpg", width: 120, height: 120 }] },
              },
            },
          },
        },
        {
          musicResponsiveListItemRenderer: {
            playlistItemData: { videoId: "track-b-456" },
            flexColumns: [
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Track B" }] } } },
              { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Titre" }, { text: " • " }, { text: "Artist B" }] } } },
            ],
            thumbnail: {
              musicThumbnailRenderer: {
                thumbnail: { thumbnails: [{ url: "https://example.com/track-b.jpg", width: 120, height: 120 }] },
              },
            },
          },
        },
      ],
    };

    const result = parsePlaylist(mockPlaylistData);

    expect(result.artwork).toBe("https://example.com/playlist.jpg");
    expect(result.tracks.map((track) => track.artwork)).toEqual([
      "https://example.com/track-a.jpg",
      "https://example.com/track-b.jpg",
    ]);
  });

  it("prefers an official square track cover over a larger video thumbnail", () => {
    const result = parseSearch({
      contents: [{
        musicResponsiveListItemRenderer: {
          playlistItemData: { videoId: "abcdefghijk" },
          flexColumns: [
            { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Song" }] } } },
            { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Titre • Artist" }] } } },
          ],
          thumbnail: {
            musicThumbnailRenderer: {
              thumbnail: { thumbnails: [
                { url: "https://lh3.googleusercontent.com/cover=w60-h60-l90-rj", width: 60, height: 60 },
                { url: "https://lh3.googleusercontent.com/cover=w544-h544-l90-rj", width: 544, height: 544 },
              ] },
            },
            thumbnails: [
              { url: "https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg", width: 1280, height: 720 },
            ],
          },
        },
      }],
    });

    expect(result[0].artwork).toBe("https://lh3.googleusercontent.com/cover=w544-h544-l90-rj");
  });

  it("uses ratio before array order and keeps a video thumbnail unchanged as last fallback", () => {
    const squareResult = parseSearch({
      contents: [{
        musicResponsiveListItemRenderer: {
          playlistItemData: { videoId: "abcdefghijk" },
          flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Song" }] } } }],
          thumbnail: { thumbnails: [
            { url: "https://example.com/cover.jpg", width: 600, height: 600 },
            { url: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg", width: 1280, height: 720 },
          ] },
        },
      }],
    });
    expect(squareResult[0].artwork).toBe("https://example.com/cover.jpg");

    const videoResult = parseSearch({
      contents: [{
        musicResponsiveListItemRenderer: {
          playlistItemData: { videoId: "abcdefghijk" },
          flexColumns: [{ musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Song" }] } } }],
          thumbnail: { thumbnails: [
            { url: "https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg", width: 480, height: 360 },
          ] },
        },
      }],
    });
    expect(videoResult[0].artwork).toBe("https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg");
  });

  it("upgrades square Music artwork without converting video thumbnails to maxresdefault", () => {
    expect(highResolutionArtwork("https://lh3.googleusercontent.com/cover=w544-h544-l90-rj"))
      .toBe("https://lh3.googleusercontent.com/cover=w1200-h1200-l90-rj");
    expect(highResolutionArtwork("https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg"))
      .toBe("https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg");
  });
});
