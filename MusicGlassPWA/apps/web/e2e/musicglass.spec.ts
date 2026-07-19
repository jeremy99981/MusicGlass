import path from "node:path";
import { expect, test, type Page } from "@playwright/test";

const artwork = "https://fixtures.musicglass.test/cover-square.svg";
const videoArtwork = "https://fixtures.musicglass.test/video-16x9.svg";

const homeFixture = {
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
              playlistItemData: { videoId: "track-1" },
              title: { runs: [{ text: "Feu de bois" }] },
              subtitle: { runs: [{ text: "Damso" }] },
              thumbnail: {
                musicThumbnailRenderer: {
                  thumbnail: { thumbnails: [{ url: videoArtwork, width: 640, height: 360 }] },
                },
              },
              thumbnailRenderer: {
                musicThumbnailRenderer: {
                  thumbnail: { thumbnails: [{ url: artwork, width: 600, height: 600 }] },
                },
              },
            },
          },
          {
            musicTwoRowItemRenderer: {
              navigationEndpoint: {
                browseEndpoint: {
                  browseId: "VLplaylist-1",
                  browseEndpointContextSupportedConfigs: {
                    browseEndpointContextMusicConfig: { pageType: "MUSIC_PAGE_TYPE_PLAYLIST" },
                  },
                },
              },
              title: { runs: [{ text: "Mix du soir" }] },
              subtitle: { runs: [{ text: "Playlist" }] },
              thumbnailRenderer: {
                musicThumbnailRenderer: {
                  thumbnail: { thumbnails: [{ url: artwork, width: 120, height: 120 }] },
                },
              },
            },
          },
        ],
      },
    },
  ],
};

const searchFixture = {
  contents: [
    {
      musicResponsiveListItemRenderer: {
        playlistItemData: { videoId: "search-track-1" },
        flexColumns: [
          { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Search Song" }] } } },
          {
            musicResponsiveListItemFlexColumnRenderer: {
              text: { runs: [{ text: "Titre" }, { text: " • " }, { text: "Search Artist" }] },
            },
          },
        ],
        thumbnail: {
          musicThumbnailRenderer: {
            thumbnail: { thumbnails: [{ url: videoArtwork, width: 640, height: 360 }] },
          },
        },
        thumbnailRenderer: {
          musicThumbnailRenderer: {
            thumbnail: { thumbnails: [{ url: artwork, width: 600, height: 600 }] },
          },
        },
      },
    },
    {
      musicResponsiveListItemRenderer: {
        navigationEndpoint: {
          browseEndpoint: {
            browseId: "artist-1",
            browseEndpointContextSupportedConfigs: {
              browseEndpointContextMusicConfig: { pageType: "MUSIC_PAGE_TYPE_ARTIST" },
            },
          },
        },
        flexColumns: [
          { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Search Artist" }] } } },
          { musicResponsiveListItemFlexColumnRenderer: { text: { runs: [{ text: "Artiste" }] } } },
        ],
        thumbnail: {
          musicThumbnailRenderer: {
            thumbnail: { thumbnails: [{ url: artwork, width: 120, height: 120 }] },
          },
        },
      },
    },
  ],
};

const detailFixture = {
  title: "Carré parfait",
  subtitle: "Album de test",
  artist: "Fixture Artist",
  artwork,
  tracks: [
    { id: "detail-track-1", title: "Piste carrée", artist: "Fixture Artist", artwork, duration_seconds: 134 },
    { id: "detail-track-2", title: "Deuxième piste", artist: "Fixture Artist", artwork, duration_seconds: 151 },
  ],
};

async function mockApi(page: Page) {
  let serverSearchHistory: Array<{ id: number; query: string; searched_at: string }> = [];
  await page.route("https://fixtures.musicglass.test/**", async (route) => {
    const square = route.request().url().includes("cover-square");
    const width = square ? 600 : 640;
    const height = square ? 600 : 360;
    await route.fulfill({
      status: 200,
      contentType: "image/svg+xml",
      body: `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><rect width="100%" height="100%" fill="${square ? "#35e477" : "#e5484d"}"/></svg>`,
    });
  });
  await page.route("**/api/v2/me", async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ id: 1, name: "Lucas", email: "lucas@example.com" }) });
  });
  await page.route("**/api/v2/search/history", async (route) => {
    const method = route.request().method();
    if (method === "POST") {
      const payload = route.request().postDataJSON() as { query: string };
      serverSearchHistory = [
        { id: Date.now(), query: payload.query, searched_at: new Date().toISOString() },
        ...serverSearchHistory.filter((entry) => entry.query.toLowerCase() !== payload.query.toLowerCase()),
      ].slice(0, 20);
      await route.fulfill({ status: 201, contentType: "application/json", body: JSON.stringify(serverSearchHistory[0]) });
      return;
    }
    if (method === "DELETE") {
      serverSearchHistory = [];
      await route.fulfill({ status: 204, body: "" });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(serverSearchHistory) });
  });
  await page.route("**/api/v2/library/playlists", async (route) => {
    if (route.request().method() === "POST") {
      await route.fulfill({ status: 201, contentType: "application/json", body: JSON.stringify({ id: 7, name: "Road trip", song_count: 0 }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify([{ id: 1, name: "Vibrations", song_count: 12 }]) });
  });
  await page.route("**/api/v2/library/likes", async (route) => {
    await route.fulfill({ status: route.request().method() === "POST" ? 201 : 200, contentType: "application/json", body: JSON.stringify([]) });
  });
  await page.route("**/api/v2/library", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        likes: [{ id: 1, song: { external_id: "track-1", title: "Feu de bois", artist: "Damso", cover_url: artwork } }],
        playlists: [{ id: 1, name: "Vibrations", song_count: 12 }],
        provider: { id: "youtube_music", name: "YouTube Music", connected: false, status: "server_setup_required", server_only: true },
      }),
    });
  });
  await page.route("**/api/v2/providers/youtube/connect", async (route) => {
    await route.fulfill({ status: 501, contentType: "application/json", body: JSON.stringify({ error: "server setup required" }) });
  });
  await page.route("**/api/v2/catalog/home", async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(homeFixture) });
  });
  await page.route("**/api/v2/catalog/search**", async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(searchFixture) });
  });
  await page.route("**/api/v2/catalog/playlist/**", async (route) => {
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(detailFixture) });
  });
  await page.route("**/api/v2/catalog/radio**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        source: "youtube_music",
        tracks: [
          { id: "radio-1", title: "Radio Next", artist: "Next Artist", album: "", artwork, duration: 24, accent: "#263443" },
          { id: "radio-2", title: "Radio After", artist: "After Artist", album: "", artwork, duration: 24, accent: "#263443" },
        ],
      }),
    });
  });
  await page.route("**/api/v2/media/resolve/**", async (route) => {
    const trackId = new URL(route.request().url()).pathname.split("/").pop() || "track-1";
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({ stream_url: `/api/v2/media/stream/${trackId}`, cached: true, duration_seconds: 134 }),
    });
  });
  await page.route("**/api/v2/media/stream/**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "audio/mp4",
      path: path.join(process.cwd(), "apps/web/public/demo-preview.m4a"),
    });
  });
  await page.route("**/api/v2/media/artwork**", async (route) => {
    await route.fulfill({
      status: 200,
      contentType: "image/svg+xml",
      body: `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="600"><rect width="600" height="600" fill="#35e477"/></svg>`,
    });
  });
}

test.beforeEach(async ({ page }) => {
  await mockApi(page);
  await page.addInitScript(() => {
    const testWindow = window as Window & {
      __failNextMediaPlay?: boolean;
      __stallNextMediaPlay?: boolean;
      __mediaPlayAttempts?: number;
      __mediaLoadCalls?: number;
      __playingMediaSlots?: Set<string>;
      __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null>;
    };
    testWindow.__mediaPlayAttempts = 0;
    testWindow.__mediaLoadCalls = 0;
    testWindow.__playingMediaSlots = new Set();
    const pausedMedia = new WeakMap<HTMLMediaElement, boolean>();
    const mediaTime = new WeakMap<HTMLMediaElement, number>();
    Object.defineProperty(HTMLMediaElement.prototype, "paused", {
      configurable: true,
      get() {
        return pausedMedia.get(this) ?? true;
      },
    });
    Object.defineProperty(HTMLMediaElement.prototype, "currentTime", {
      configurable: true,
      get() {
        return mediaTime.get(this) ?? 0;
      },
      set(value: number) {
        mediaTime.set(this, Number.isFinite(value) ? Math.max(0, value) : 0);
      },
    });
    HTMLMediaElement.prototype.play = function play() {
      testWindow.__mediaPlayAttempts = (testWindow.__mediaPlayAttempts ?? 0) + 1;
      if (testWindow.__failNextMediaPlay) {
        testWindow.__failNextMediaPlay = false;
        return Promise.reject(new DOMException("iOS discarded the background media resource", "AbortError"));
      }
      pausedMedia.set(this, false);
      testWindow.__playingMediaSlots?.add(this.dataset.audioSlot ?? "unknown");
      this.dispatchEvent(new Event("play"));
      this.dispatchEvent(new Event("playing"));
      if (testWindow.__stallNextMediaPlay) {
        testWindow.__stallNextMediaPlay = false;
      } else {
        window.setTimeout(() => {
          if (!(pausedMedia.get(this) ?? true)) mediaTime.set(this, (mediaTime.get(this) ?? 0) + 0.25);
        }, 25);
      }
      return Promise.resolve();
    };
    HTMLMediaElement.prototype.pause = function pause() {
      pausedMedia.set(this, true);
      testWindow.__playingMediaSlots?.delete(this.dataset.audioSlot ?? "unknown");
      this.dispatchEvent(new Event("pause"));
    };
    const nativeLoad = HTMLMediaElement.prototype.load;
    HTMLMediaElement.prototype.load = function load() {
      testWindow.__mediaLoadCalls = (testWindow.__mediaLoadCalls ?? 0) + 1;
      nativeLoad.call(this);
      window.setTimeout(() => this.dispatchEvent(new Event("canplay")), 0);
    };

    if ("mediaSession" in navigator) {
      const handlers = new Map<string, MediaSessionActionHandler | null>();
      const nativeSetActionHandler = navigator.mediaSession.setActionHandler.bind(navigator.mediaSession);
      testWindow.__mediaSessionHandlers = handlers;
      navigator.mediaSession.setActionHandler = ((action: MediaSessionAction, handler: MediaSessionActionHandler | null) => {
        handlers.set(action, handler);
        nativeSetActionHandler(action, handler);
      }) as typeof navigator.mediaSession.setActionHandler;
    }
  });
});

async function expectSquareArtwork(page: Page, selector: string) {
  const image = page.locator(selector).first();
  await expect(image).toBeVisible();
  await expect(image).toHaveAttribute("src", artwork);
  const dimensions = await image.evaluate((element: HTMLImageElement) => ({
    complete: element.complete,
    naturalWidth: element.naturalWidth,
    naturalHeight: element.naturalHeight,
    renderedWidth: element.getBoundingClientRect().width,
    renderedHeight: element.getBoundingClientRect().height,
    currentSrc: element.currentSrc,
  }));
  expect(dimensions.complete).toBe(true);
  expect(dimensions.naturalWidth).toBeGreaterThan(0);
  expect(dimensions.naturalWidth).toBe(dimensions.naturalHeight);
  expect(Math.abs(dimensions.renderedWidth - dimensions.renderedHeight)).toBeLessThanOrEqual(1);
  expect(dimensions.currentSrc).not.toContain("i.ytimg.com/vi/");
}

test("loads the home catalog and starts the mini-player", async ({ page }) => {
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Accueil", exact: true })).toBeVisible();
  await expect(page.getByText(/bonjour|bon après-midi|bonsoir/i).first()).toBeVisible();
  await expect(page.getByRole("heading", { name: "Pour vous" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Le son qui rapproche." })).not.toBeVisible();
  const feuDeBoisCard = page.locator(".shelf-card").filter({ hasText: "Feu de bois" }).first();
  await expect(feuDeBoisCard).toBeVisible();

  await feuDeBoisCard.click();

  await expect(page.getByRole("region", { name: "Lecteur audio" })).toBeVisible();
  await expect(page.getByRole("region", { name: "Lecteur audio" }).getByText("Feu de bois")).toBeVisible();
  await expect(page.getByRole("button", { name: "Pause" })).toBeVisible();

  if (test.info().project.name.includes("mobile")) {
    const miniBox = await page.getByRole("region", { name: "Lecteur audio" }).boundingBox();
    const navBox = await page.locator(".mobile-nav").boundingBox();
    expect(miniBox).not.toBeNull();
    expect(navBox).not.toBeNull();
    expect((miniBox?.y ?? 0) + (miniBox?.height ?? 0)).toBeLessThanOrEqual((navBox?.y ?? 0) - 14);
  }
});

test("recovers one stalled iOS native play without reloading normal plays", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(navigator, "userAgent", {
      configurable: true,
      value: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148 Safari/604.1",
    });
    Object.defineProperty(navigator, "audioSession", {
      configurable: true,
      value: { type: "ambient" },
    });
  });
  await page.goto("/");
  await page.locator(".shelf-card").filter({ hasText: "Feu de bois" }).first().click();
  const player = page.getByRole("region", { name: "Lecteur audio" });
  await expect(player.getByRole("button", { name: "Pause" })).toBeVisible();

  const transportHandlers = await page.evaluate(() => {
    const handlers = (window as Window & { __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null> }).__mediaSessionHandlers;
    return {
      play: typeof handlers?.get("play"),
      pause: typeof handlers?.get("pause"),
      next: typeof handlers?.get("nexttrack"),
      previous: typeof handlers?.get("previoustrack"),
    };
  });
  expect(transportHandlers).toEqual({ play: "function", pause: "function", next: "function", previous: "function" });

  const activeAudio = page.locator('audio[data-audio-active="true"]');
  const activeSlotBeforeResume = await activeAudio.getAttribute("data-audio-slot");
  expect(await page.locator("audio").count()).toBe(1);
  await expect.poll(() => page.evaluate(() => (
    navigator as Navigator & { audioSession?: { type: string } }
  ).audioSession?.type)).toBe("playback");
  await expect.poll(() => page.evaluate(() => navigator.mediaSession.metadata?.artwork[0]?.src ?? "")).toContain("/api/v2/media/artwork?url=");
  // Let the initial successful-play verification complete before simulating a
  // distinct user action from Control Center.
  await page.waitForTimeout(3000);

  const loadCallsBeforeRecovery = await page.evaluate(() => (
    (window as Window & { __mediaLoadCalls?: number }).__mediaLoadCalls ?? 0
  ));
  const playCallsBeforeRecovery = await page.evaluate(() => (
    (window as Window & { __mediaPlayAttempts?: number }).__mediaPlayAttempts ?? 0
  ));
  await page.evaluate(() => {
    const testWindow = window as Window & {
      __stallNextMediaPlay?: boolean;
      __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null>;
      __audioRecoveryEvents?: Array<{ event: string; reason?: string }>;
    };
    testWindow.__audioRecoveryEvents = [];
    window.addEventListener("musicglass:audio-recovery", ((event: CustomEvent<{ event: string; reason?: string }>) => {
      testWindow.__audioRecoveryEvents?.push(event.detail);
    }) as EventListener);
    testWindow.__mediaSessionHandlers?.get("pause")?.({ action: "pause" });
    testWindow.__stallNextMediaPlay = true;
    testWindow.__mediaSessionHandlers?.get("play")?.({ action: "play" });
  });

  await expect.poll(() => page.evaluate(() => (
    (window as Window & { __mediaPlayAttempts?: number }).__mediaPlayAttempts ?? 0
  ))).toBe(playCallsBeforeRecovery + 1);

  await expect.poll(() => page.evaluate(() => (
    (window as Window & { __audioRecoveryEvents?: Array<{ event: string; reason?: string }> }).__audioRecoveryEvents
      ?.map(({ event, reason }) => ({ event, reason })) ?? []
  )), { timeout: 10_000 }).toEqual([
    { event: "audio_recovery_started", reason: undefined },
    { event: "audio_recovery_succeeded", reason: undefined },
  ]);
  await expect.poll(() => page.evaluate(() => (
    (window as Window & { __mediaLoadCalls?: number }).__mediaLoadCalls ?? 0
  ))).toBe(loadCallsBeforeRecovery + 1);
  await expect(activeAudio).toHaveAttribute("src", /resume=/);
  await expect(player.getByRole("button", { name: "Pause" })).toBeVisible();
  await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("playing");

  for (let cycle = 0; cycle < 3; cycle += 1) {
    const loadCallsBeforeNormalPlay = await page.evaluate(() => (
      (window as Window & { __mediaLoadCalls?: number }).__mediaLoadCalls ?? 0
    ));
    await page.evaluate(() => {
      const handlers = (window as Window & { __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null> }).__mediaSessionHandlers;
      handlers?.get("pause")?.({ action: "pause" });
    });
    await expect(player.getByRole("button", { name: "Lecture" })).toBeVisible();
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("paused");

    await page.evaluate(() => {
      const handlers = (window as Window & { __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null> }).__mediaSessionHandlers;
      handlers?.get("play")?.({ action: "play" });
    });
    await expect(player.getByRole("button", { name: "Pause" })).toBeVisible();
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("playing");
    await expect.poll(() => page.evaluate(() => (
      (window as Window & { __playingMediaSlots?: Set<string> }).__playingMediaSlots?.size ?? 0
    ))).toBe(1);
    await expect(activeAudio).toHaveAttribute("data-audio-slot", activeSlotBeforeResume ?? "");
    await page.waitForTimeout(1450);
    await expect.poll(() => page.evaluate(() => (
      (window as Window & { __mediaLoadCalls?: number }).__mediaLoadCalls ?? 0
    ))).toBe(loadCallsBeforeNormalPlay);
  }

  const sourceDuringNativeNext = await page.evaluate(() => {
    const handlers = (window as Window & { __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null> }).__mediaSessionHandlers;
    handlers?.get("nexttrack")?.({ action: "nexttrack" });
    return document.querySelector<HTMLAudioElement>('audio[data-audio-active="true"]')?.getAttribute("src") ?? "";
  });
  expect(sourceDuringNativeNext).toContain("/api/v2/media/stream/radio-1");
  await expect(player.getByText("Radio Next", { exact: true })).toBeVisible();
  await expect(player.getByRole("button", { name: "Pause" })).toBeVisible();

  const sourceDuringNativePrevious = await page.evaluate(() => {
    const handlers = (window as Window & { __mediaSessionHandlers?: Map<string, MediaSessionActionHandler | null> }).__mediaSessionHandlers;
    handlers?.get("previoustrack")?.({ action: "previoustrack" });
    return document.querySelector<HTMLAudioElement>('audio[data-audio-active="true"]')?.getAttribute("src") ?? "";
  });
  expect(sourceDuringNativePrevious).toContain("/api/v2/media/stream/track-1");
  await expect(player.getByText("Feu de bois", { exact: true })).toBeVisible();
});

test("keeps loading AutoMix while a saved shared session reconnects", async ({ page }) => {
  await page.addInitScript(() => {
    window.localStorage.setItem("musicglass-shared-session-v1", JSON.stringify({
      state: { code: "TEST42", isHost: false },
      version: 0,
    }));
  });
  await page.route("**/api/v2/catalog/radio**", async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 500));
    await route.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify({
        source: "youtube_music_next",
        tracks: [
          { id: "radio-1", title: "Radio Next", artist: "Next Artist", album: "", artwork, duration: 24, accent: "#263443" },
          { id: "radio-2", title: "Radio After", artist: "After Artist", album: "", artwork, duration: 24, accent: "#263443" },
        ],
      }),
    });
  });

  await page.goto("/");
  await page.locator(".shelf-card").filter({ hasText: "Feu de bois" }).first().click();
  await page.getByRole("region", { name: "Lecteur audio" }).getByRole("button", { name: /feu de bois/i }).click();
  await page.locator(".full-player").getByRole("button", { name: /ouvrir la file d’attente/i }).first().click();

  const queueDialog = page.getByRole("dialog", { name: "File d’attente" });
  await expect(queueDialog.getByText("Radio Next", { exact: true })).toBeVisible();
  await expect(queueDialog.getByText("Recherche de titres proches...")).toBeHidden();
});

test("uses official square artwork throughout playback", async ({ page }) => {
  await page.goto("/");
  await expectSquareArtwork(page, '.shelf-card:has-text("Feu de bois") .shelf-card-art img');
  await expectSquareArtwork(page, '.home-quick-grid > button:has-text("Feu de bois") img');

  await page.locator('.shelf-card:has-text("Feu de bois")').first().click();
  const miniPlayer = page.getByRole("region", { name: "Lecteur audio" });
  await expectSquareArtwork(page, '[role="region"][aria-label="Lecteur audio"] .mini-artwork-wrap img');
  await expect(miniPlayer).toHaveAttribute("style", /--mini-artwork:/);
  await page.getByRole("region", { name: "Lecteur audio" }).getByRole("button", { name: /feu de bois/i }).click();
  await page.waitForTimeout(300);
  await expectSquareArtwork(page, ".fp-artwork-frame img");
  await expect(page.locator(".full-player")).toHaveAttribute("style", /--player-artwork:/);
  await expect(page.locator(".fp-glow")).toHaveCount(0);

  await page.goto("/playlist/playlist-1");
  await expect(page.getByRole("heading", { name: "Carré parfait" })).toBeVisible();
  await expectSquareArtwork(page, ".detail-cover");
  await expectSquareArtwork(page, '.detail-track-list .track-row:has-text("Piste carrée") .track-art img');
});

test("loads playlist, album, and artist detail pages from the canonical catalog response", async ({ page }) => {
  for (const route of ["/playlist/OLAK5uy_fixture", "/album/OLAK5uy_fixture"]) {
    await page.goto(route);
    await expect(page.getByRole("heading", { name: "Carré parfait" })).toBeVisible();
    await expect(page.getByText("Piste carrée", { exact: true })).toBeVisible();
  }

  await page.goto("/artist/UCartist-fixture");
  await expect(page.getByRole("heading", { name: "Carré parfait" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Titres populaires" })).toBeVisible();
  await expect(page.getByText("Piste carrée", { exact: true })).toBeVisible();
  await expect(page.getByText("Impossible de charger l’artiste.")).toHaveCount(0);
});

test("keeps the desktop shell structured and centered", async ({ page }) => {
  test.skip(page.viewportSize()!.width < 1024, "Desktop contract");
  await page.goto("/");
  await expect(page.locator(".desktop-sidebar")).toBeVisible();
  await expect(page.locator(".mobile-nav")).toBeHidden();

  const [sidebar, content, pageRoot] = await Promise.all([
    page.locator(".desktop-sidebar").boundingBox(),
    page.locator(".page-content").boundingBox(),
    page.locator(".page-content .page").first().boundingBox(),
  ]);
  expect(sidebar).not.toBeNull();
  expect(content).not.toBeNull();
  expect(pageRoot).not.toBeNull();
  expect(sidebar!.x).toBeGreaterThanOrEqual(0);
  expect(sidebar!.x).toBeLessThanOrEqual(16);
  expect(content!.x).toBeGreaterThanOrEqual(sidebar!.x + sidebar!.width - 1);
  expect(content!.x + content!.width).toBeLessThanOrEqual(page.viewportSize()!.width + 1);
  expect(pageRoot!.x).toBeGreaterThanOrEqual(content!.x);
  expect(pageRoot!.x + pageRoot!.width).toBeLessThanOrEqual(page.viewportSize()!.width + 1);
});

test("navigates between main sections", async ({ page }) => {
  await page.goto("/");

  await page.locator('nav a[href="/search"]:visible').click();
  await expect(page).toHaveURL(/\/search/);
  await expect(page.getByRole("heading", { name: "Recherche", exact: true })).toBeVisible();

  await page.locator('nav a[href="/library"]:visible').click();
  await expect(page).toHaveURL(/\/library/);
  await expect(page.getByRole("heading", { name: "Bibliothèque" })).toBeVisible();
});

test("searches and plays a result", async ({ page }) => {
  await page.goto("/search");

  await expect(page.getByRole("heading", { name: "Recherches récentes" })).toBeVisible();
  await expect(page.getByText("Votre historique apparaîtra ici")).toBeVisible();

  await page.getByPlaceholder("Que voulez-vous écouter ?").fill("search");
  await expect(page.getByText("Search Song").first()).toBeVisible();
  await expect(page.getByRole("article").filter({ hasText: "Search Song" }).getByText("Search Artist")).toBeVisible();
  await expect(page.getByText("Titre •", { exact: true })).toHaveCount(0);

  await page.getByPlaceholder("Que voulez-vous écouter ?").fill("");
  await expect(page.getByRole("button", { name: /search/i }).filter({ hasText: "search" })).toBeVisible();
  await page.getByRole("button", { name: /search/i }).filter({ hasText: "search" }).click();
  await expect(page.getByText("Search Song").first()).toBeVisible();

  await page.getByRole("article").filter({ hasText: "Search Song" }).getByRole("button").first().click();
  await expect(page.getByRole("region", { name: "Lecteur audio" }).getByText("Search Song")).toBeVisible();
  await expect.poll(async () => page.evaluate(() => {
    const raw = localStorage.getItem("musicglass-playback-v2");
    return raw ? JSON.parse(raw).state.queue.map((track: { title: string }) => track.title) : [];
  })).toEqual(["Search Song", "Radio Next", "Radio After"]);
});

test("opens the full player queue on mobile and desktop", async ({ page }) => {
  await page.goto("/");
  await page.locator(".shelf-card").filter({ hasText: "Feu de bois" }).first().click();
  await page.getByRole("region", { name: "Lecteur audio" }).getByRole("button", { name: /feu de bois/i }).click();

  const fullPlayer = page.locator(".full-player");
  await expect(fullPlayer.locator(".fp-header-label strong")).toHaveText("Feu de bois");
  await expect(fullPlayer.locator(".fp-title")).toHaveText("Feu de bois");
  await expect(fullPlayer.locator(".fp-artist-name")).toHaveText("Damso");
  await expect(fullPlayer.locator(".fp-time-labels time").last()).toHaveText("-2:14");
  const fullPlayerQueueButton = page.viewportSize()!.width < 800
    ? fullPlayer.locator(".fp-mobile-actions").getByRole("button", { name: /ouvrir la file d.attente/i })
    : fullPlayer.locator(".fp-queue-action");
  await expect(fullPlayerQueueButton).toBeVisible();
  await page.waitForTimeout(300);
  const artworkBox = await page.locator(".fp-artwork-frame").boundingBox();
  const infoBox = await page.locator(".fp-info").boundingBox();
  expect(artworkBox).not.toBeNull();
  expect(infoBox).not.toBeNull();
  expect(artworkBox!.y + artworkBox!.height).toBeLessThanOrEqual(page.viewportSize()!.height + 1);
  expect(infoBox!.y + infoBox!.height).toBeLessThanOrEqual(page.viewportSize()!.height + 1);
  if (page.viewportSize()!.width >= 1024) {
    const minimumArtworkWidth = page.viewportSize()!.width <= 1190 ? 300 : 360;
    expect(artworkBox!.width).toBeGreaterThanOrEqual(minimumArtworkWidth);
  }
  if (process.env.VISUAL_AUDIT === "1") {
    await page.screenshot({ path: test.info().outputPath("full-player.png") });
  }
  await fullPlayerQueueButton.click();
  const queueDialog = page.getByRole("dialog", { name: "File d’attente" });
  await expect(queueDialog).toBeVisible();
  if (process.env.VISUAL_AUDIT === "1") {
    await page.waitForTimeout(300);
    await page.screenshot({ path: test.info().outputPath("queue.png") });
  }
  await page.waitForTimeout(250);
  const queueBox = await queueDialog.boundingBox();
  expect(queueBox).not.toBeNull();
  expect((queueBox?.y ?? 0) + (queueBox?.height ?? 0)).toBeLessThanOrEqual(page.viewportSize()!.height + 1);
  if (page.viewportSize()!.width < 1024) {
    expect(queueBox?.y ?? -1).toBeLessThanOrEqual(1);
    expect(queueBox?.height ?? 0).toBeGreaterThanOrEqual(page.viewportSize()!.height - 1);
    expect(queueBox?.x ?? -1).toBeLessThanOrEqual(1);
    expect(queueBox?.width ?? 0).toBeGreaterThanOrEqual(page.viewportSize()!.width - 1);
    const queuePlayback = queueDialog.locator(".queue-mobile-footer");
    await expect(queuePlayback).toBeVisible();
    await queuePlayback.getByRole("button", { name: "Pause", exact: true }).click();
    await expect(queuePlayback.getByRole("button", { name: "Lecture", exact: true })).toBeVisible();
  }
  await expect(queueDialog.getByText(/^En cours/)).toBeVisible();
  await expect(queueDialog.getByText(/^À suivre/)).toBeVisible();
  await expect(queueDialog.getByText("Next Artist", { exact: true })).toBeVisible();
  await expect(queueDialog.getByText(/^\d+\. Next Artist$/)).toHaveCount(0);
  await expect(page.getByText("Pochette officielle")).toHaveCount(0);
  await expect(page.getByText("Artiste inconnu")).toHaveCount(0);
  await expect(queueDialog.getByRole("button", { name: /plus d.actions/i })).toHaveCount(0);
  await queueDialog.getByRole("button", { name: /lire radio next/i }).click();
  await expect(queueDialog.locator(".queue-current").getByText("Radio Next")).toBeVisible();
});

test("opens the queue directly from the desktop control center", async ({ page }) => {
  test.skip(page.viewportSize()!.width < 1024, "Desktop control center contract");
  await page.goto("/");
  await page.locator(".shelf-card").filter({ hasText: "Feu de bois" }).first().click();

  const player = page.getByRole("region", { name: "Lecteur audio" });
  await expect(player.getByRole("slider", { name: "Position de lecture" })).toBeVisible();
  await player.getByRole("button", { name: /ouvrir la file d’attente/i }).click();

  const queueDialog = page.getByRole("dialog", { name: "File d’attente" });
  await expect(queueDialog).toBeVisible();
  await expect(page.locator(".full-player")).toBeHidden();
  if (page.viewportSize()!.width >= 1280) {
    await expect(page.locator(".queue-backdrop")).toHaveClass(/queue-docked/);
    await expect(queueDialog).not.toHaveAttribute("aria-modal");
  }
});

test("uses the resolved duration and advances only once on duplicate ended events", async ({ page }) => {
  await page.goto("/");
  await page.locator(".shelf-card").filter({ hasText: "Feu de bois" }).first().click();
  await page.getByRole("region", { name: "Lecteur audio" }).getByRole("button", { name: /feu de bois/i }).click();

  await expect(page.locator(".fp-time-labels").getByText("2:14")).toBeVisible();
  await page.locator('audio[data-audio-active="true"]').evaluate((audio) => {
    audio.dispatchEvent(new Event("ended"));
    audio.dispatchEvent(new Event("ended"));
  });
  await expect(page.locator(".fp-title")).toHaveText("Radio Next");
  await expect(page.locator(".fp-title")).not.toHaveText("Radio After");
});

test("keeps every page inside the viewport", async ({ page }) => {
  const routes = ["/", "/search", "/library", "/settings", "/login", "/artist/artist-1", "/album/album-1", "/playlist/playlist-1"];
  for (const route of routes) {
    await page.goto(route);
    await page.waitForLoadState("networkidle");
    if (process.env.VISUAL_AUDIT === "1") {
      const slug = route === "/" ? "home" : route.replace(/^\//, "").replaceAll("/", "-");
      await page.screenshot({ path: test.info().outputPath(`${slug}.png`), fullPage: false });
    }
    const dimensions = await page.evaluate(() => ({
      viewport: document.documentElement.clientWidth,
      document: document.documentElement.scrollWidth,
      body: document.body.scrollWidth,
      offenders: [...document.querySelectorAll<HTMLElement>("body *")]
        .map((element) => ({
          name: `${element.tagName.toLowerCase()}.${element.className}`,
          left: Math.round(element.getBoundingClientRect().left),
          right: Math.round(element.getBoundingClientRect().right),
        }))
        .filter((element) => element.left < -1 || element.right > document.documentElement.clientWidth + 1)
        .slice(0, 8),
    }));
    expect(dimensions.document, `${route} document overflow: ${JSON.stringify(dimensions.offenders)}`).toBeLessThanOrEqual(dimensions.viewport + 1);
    expect(dimensions.body, `${route} body overflow: ${JSON.stringify(dimensions.offenders)}`).toBeLessThanOrEqual(dimensions.viewport + 1);
    if (page.viewportSize()!.width < 1024 && route !== "/login") {
      const mobileNav = page.locator(".mobile-nav");
      const mobileNavBox = await mobileNav.boundingBox();
      expect(mobileNavBox, `${route} mobile navigation`).not.toBeNull();
      const expectedNavWidth = Math.min(560, page.viewportSize()!.width * 0.85);
      expect(mobileNavBox!.width, `${route} mobile navigation width`).toBeGreaterThanOrEqual(expectedNavWidth);
      await expect(mobileNav.locator("a")).toHaveCount(4);
      for (const link of await mobileNav.locator("a").all()) await expect(link).toBeVisible();
    }
  }

  await page.goto("/settings");
  await expect(page.getByRole("link", { name: /se connecter/i })).toBeVisible();
  if (page.viewportSize()!.width < 1024) {
    await expect(page.locator('.mobile-nav a[href="/settings"]')).toBeVisible();
  }

  await page.goto("/album/album-1");
  const back = await page.getByRole("button", { name: "Retour" }).boundingBox();
  expect(back).not.toBeNull();
  if (page.viewportSize()!.width >= 1024) expect(back!.x).toBeGreaterThanOrEqual(252);
});

test("keeps search results and filter controls inside the mobile viewport", async ({ page }) => {
  await page.goto("/search");
  const searchInput = page.getByPlaceholder("Que voulez-vous écouter ?");
  await searchInput.fill("search");
  await expect(page.getByRole("heading", { name: "Titres" })).toBeVisible();

  const layout = await searchInput.evaluate((input) => {
    const viewport = document.documentElement.clientWidth;
    const filterButtons = [...document.querySelectorAll<HTMLElement>("nav button")].map((button) => {
      const box = button.getBoundingClientRect();
      return { left: box.left, right: box.right };
    });
    const inputStyle = window.getComputedStyle(input);
    const containerStyle = input.parentElement ? window.getComputedStyle(input.parentElement) : null;
    return {
      viewport,
      document: document.documentElement.scrollWidth,
      body: document.body.scrollWidth,
      filterButtons,
      inputOutline: inputStyle.outlineStyle,
      inputOutlineWidth: inputStyle.outlineWidth,
      containerBorderColor: containerStyle?.borderColor ?? "",
    };
  });

  expect(layout.document).toBeLessThanOrEqual(layout.viewport + 1);
  expect(layout.body).toBeLessThanOrEqual(layout.viewport + 1);
  expect(layout.inputOutline).toBe("none");
  expect(layout.inputOutlineWidth).toBe("0px");
  expect(layout.containerBorderColor).not.toBe("rgb(49, 231, 125)");
  for (const button of layout.filterButtons) {
    expect(button.left).toBeGreaterThanOrEqual(-1);
    expect(button.right).toBeLessThanOrEqual(layout.viewport + 1);
  }
});

test("shows backend library and YouTube Music provider state", async ({ page }) => {
  await page.goto("/library");

  await expect(page.getByRole("heading", { name: "Bibliothèque" })).toBeVisible();
  await expect(page.getByText("Lecture publique sans compte")).toBeVisible();
  await expect(page.getByText("Vibrations")).toBeVisible();
  await expect(page.getByText("Feu de bois").first()).toBeVisible();

  await page.getByPlaceholder("Nom de playlist").fill("Road trip");
  await page.locator(".library-create").getByRole("button", { name: "Créer" }).click();
  await expect(page.getByPlaceholder("Nom de playlist")).toHaveValue("");
});
