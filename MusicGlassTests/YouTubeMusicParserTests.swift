import XCTest
@testable import MusicGlass

final class YouTubeMusicParserTests: XCTestCase {
    func testMapsSongFromResponsiveRendererFixture() throws {
        let data = Data(Self.searchFixture.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let result = InnerTubeJSONMapper().mapSearchResult(from: json)

        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks.first?.videoId, "video123")
        XCTAssertEqual(result.tracks.first?.title, "Night Drive")
        XCTAssertEqual(result.tracks.first?.artists.first?.name, "Glass Artist")
        XCTAssertEqual(result.tracks.first?.duration, 184)
    }

    func testMapsPlayerPayloadBestAudioUrl() throws {
        let data = Data(Self.playerFixture.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let payload = InnerTubeJSONMapper().mapPlayerPayload(from: json, videoId: "video123")

        XCTAssertEqual(payload.playabilityStatus, "OK")
        XCTAssertEqual(payload.bestAudioURL?.absoluteString, "https://example.com/high.m4a")
    }

    func testMapsAlbumArtistsFromHeaderWhenTrackRowsDoNotExposeArtists() throws {
        let data = Data(Self.albumFixture.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let album = InnerTubeJSONMapper().mapAlbum(from: json, browseId: "album123")

        XCTAssertEqual(album.title, "Velvet Hours")
        XCTAssertEqual(album.artists.map(\.name), ["Glass Artist"])
        XCTAssertEqual(album.year, 2024)
    }

    func testMapsTrackArtistsFromLongBylineFallback() throws {
        let data = Data(Self.longBylineFixture.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let result = InnerTubeJSONMapper().mapSearchResult(from: json)

        XCTAssertEqual(result.tracks.count, 1)
        XCTAssertEqual(result.tracks.first?.artists.map(\.name), ["Midnight Waves"])
    }

    func testMapsPlaylistTrackArtistsFromSecondFlexColumnAndDurationFromFixedColumn() throws {
        let data = Data(Self.playlistFixture.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let playlist = InnerTubeJSONMapper().mapPlaylist(from: json, browseId: "playlist123")

        XCTAssertEqual(playlist.tracks.count, 1)
        XCTAssertEqual(playlist.tracks.first?.title, "TQG")
        XCTAssertEqual(playlist.tracks.first?.artists.map(\.name), ["KAROL G", "Shakira"])
        XCTAssertEqual(playlist.tracks.first?.duration, 217)
    }

    private static let searchFixture = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": [{
                    "musicShelfRenderer": {
                      "contents": [{
                        "musicResponsiveListItemRenderer": {
                          "playlistItemData": { "videoId": "video123" },
                          "flexColumns": [
                            { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Night Drive" }] } } },
                            { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [
                              { "text": "Glass Artist", "navigationEndpoint": { "browseEndpoint": {
                                "browseId": "artist123",
                                "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" } }
                              } } },
                              { "text": " • " },
                              { "text": "3:04" }
                            ] } } }
                          ],
                          "thumbnail": { "musicThumbnailRenderer": { "thumbnail": { "thumbnails": [
                            { "url": "https://example.com/art.jpg", "width": 120, "height": 120 }
                          ] } } }
                        }
                      }]
                    }
                  }]
                }
              }
            }
          }]
        }
      }
    }
    """

    private static let playerFixture = """
    {
      "playabilityStatus": { "status": "OK" },
      "videoDetails": {
        "videoId": "video123",
        "title": "Night Drive",
        "author": "Glass Artist",
        "lengthSeconds": "184",
        "thumbnail": { "thumbnails": [] }
      },
      "streamingData": {
        "adaptiveFormats": [
          { "itag": 251, "mimeType": "audio/webm; codecs=\\"opus\\"", "bitrate": 160000, "url": "https://example.com/audio.webm" },
          { "itag": 140, "mimeType": "audio/mp4; codecs=\\"mp4a.40.2\\"", "bitrate": 128000, "url": "https://example.com/high.m4a" }
        ]
      }
    }
    """

    private static let albumFixture = """
    {
      "header": {
        "musicDetailHeaderRenderer": {
          "title": { "runs": [{ "text": "Velvet Hours" }] },
          "subtitle": {
            "runs": [
              { "text": "Glass Artist", "navigationEndpoint": { "browseEndpoint": {
                "browseId": "artist123",
                "browseEndpointContextSupportedConfigs": { "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" } }
              } } },
              { "text": " • " },
              { "text": "2024" }
            ]
          }
        }
      },
      "contents": [{
        "musicResponsiveListItemRenderer": {
          "playlistItemData": { "videoId": "albumTrack123" },
          "flexColumns": [
            { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "First Light" }] } } },
            { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "3:11" }] } } }
          ]
        }
      }]
    }
    """

    private static let longBylineFixture = """
    {
      "contents": {
        "tabbedSearchResultsRenderer": {
          "tabs": [{
            "tabRenderer": {
              "content": {
                "sectionListRenderer": {
                  "contents": [{
                    "musicShelfRenderer": {
                      "contents": [{
                        "musicResponsiveListItemRenderer": {
                          "playlistItemData": { "videoId": "video456" },
                          "flexColumns": [
                            { "musicResponsiveListItemFlexColumnRenderer": { "text": { "runs": [{ "text": "Moonline" }] } } }
                          ],
                          "longBylineText": {
                            "runs": [
                              { "text": "Midnight Waves" },
                              { "text": " • " },
                              { "text": "4:20" }
                            ]
                          }
                        }
                      }]
                    }
                  }]
                }
              }
            }
          }]
        }
      }
    }
    """

    private static let playlistFixture = """
    {
      "header": {
        "musicEditablePlaylistDetailHeaderRenderer": {
          "title": { "runs": [{ "text": "Cure de soleil" }] },
          "subtitle": { "runs": [{ "text": "Playlist" }, { "text": " • " }, { "text": "2026" }] }
        }
      },
      "contents": [{
        "musicResponsiveListItemRenderer": {
          "playlistItemData": { "videoId": "jZGpkLElSu8" },
          "thumbnail": {
            "musicThumbnailRenderer": {
              "thumbnail": {
                "thumbnails": [
                  { "url": "https://example.com/tqg.jpg", "width": 400, "height": 225 }
                ]
              }
            }
          },
          "flexColumns": [
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": { "runs": [{ "text": "TQG" }] }
              }
            },
            {
              "musicResponsiveListItemFlexColumnRenderer": {
                "text": {
                  "runs": [
                    {
                      "text": "KAROL G",
                      "navigationEndpoint": {
                        "browseEndpoint": {
                          "browseId": "artist-karol",
                          "browseEndpointContextSupportedConfigs": {
                            "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" }
                          }
                        }
                      }
                    },
                    { "text": " et " },
                    {
                      "text": "Shakira",
                      "navigationEndpoint": {
                        "browseEndpoint": {
                          "browseId": "artist-shakira",
                          "browseEndpointContextSupportedConfigs": {
                            "browseEndpointContextMusicConfig": { "pageType": "MUSIC_PAGE_TYPE_ARTIST" }
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          ],
          "fixedColumns": [
            {
              "musicResponsiveListItemFixedColumnRenderer": {
                "text": { "runs": [{ "text": "3:37" }] }
              }
            }
          ]
        }
      }]
    }
    """
}
