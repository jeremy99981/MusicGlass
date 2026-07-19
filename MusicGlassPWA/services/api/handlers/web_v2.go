package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	"app/middleware"
	"app/services"
	"github.com/gin-gonic/gin"
	"github.com/kkdai/youtube/v2"
)

const refreshCookie = "mg_refresh"

type streamCacheEntry struct {
	URL             string
	MimeType        string
	Source          string
	DurationSeconds int
	ExpiresAt       time.Time
}

var streamCache = struct {
	sync.RWMutex
	values map[string]streamCacheEntry
}{values: map[string]streamCacheEntry{}}

type webTrack struct {
	ID                     string `json:"id"`
	Title                  string `json:"title"`
	Artist                 string `json:"artist"`
	Album                  string `json:"album"`
	Artwork                string `json:"artwork"`
	Duration               int    `json:"duration"`
	Accent                 string `json:"accent"`
	needsArtworkEnrichment bool
}

type webLoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}
type webSignupRequest struct {
	Name     string `json:"name" binding:"required,min=2,max=255"`
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8,max=128"`
}
type webRefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func cookieSecure() bool { return strings.EqualFold(os.Getenv("COOKIE_SECURE"), "true") }

func cookieSameSite() http.SameSite {
	if strings.EqualFold(os.Getenv("COOKIE_SAMESITE"), "none") {
		return http.SameSiteNoneMode
	}
	return http.SameSiteLaxMode
}

func setWebCookies(c *gin.Context, access, refresh string) string {
	secure := cookieSecure()
	c.SetSameSite(cookieSameSite())
	c.SetCookie(middleware.AccessCookie, access, 15*60, "/", "", secure, true)
	c.SetCookie(refreshCookie, refresh, 7*24*60*60, "/api/v2/auth", "", secure, true)
	csrfBytes := make([]byte, 24)
	_, _ = rand.Read(csrfBytes)
	csrf := base64.RawURLEncoding.EncodeToString(csrfBytes)
	c.SetCookie(middleware.CSRFCookie, csrf, 7*24*60*60, "/", "", secure, false)
	return csrf
}

func clearWebCookies(c *gin.Context) {
	c.SetSameSite(cookieSameSite())
	secure := cookieSecure()
	c.SetCookie(middleware.AccessCookie, "", -1, "/", "", secure, true)
	c.SetCookie(refreshCookie, "", -1, "/api/v2/auth", "", secure, true)
	c.SetCookie(middleware.CSRFCookie, "", -1, "/", "", secure, false)
}

func (h *Handler) WebLogin(c *gin.Context) {
	var req webLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	access, refresh, err := h.auth.Login(req.Email, req.Password)
	if err != nil {
		if err == services.ErrInvalidCredentials {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid credentials"})
			return
		}
		internalError(c, err)
		return
	}
	csrf := setWebCookies(c, access, refresh)
	c.JSON(http.StatusOK, gin.H{"authenticated": true, "csrf_token": csrf, "access_token": access, "refresh_token": refresh})
}

func (h *Handler) WebSignup(c *gin.Context) {
	var req webSignupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
		return
	}
	if _, err := h.users.Create(req.Name, req.Email, req.Password); err != nil {
		if errors.Is(err, services.ErrEmailAlreadyExists) {
			c.JSON(http.StatusConflict, gin.H{"error": "email already exists"})
			return
		}
		internalError(c, err)
		return
	}
	access, refresh, err := h.auth.Login(req.Email, req.Password)
	if err != nil {
		internalError(c, err)
		return
	}
	csrf := setWebCookies(c, access, refresh)
	c.JSON(http.StatusCreated, gin.H{"authenticated": true, "csrf_token": csrf, "access_token": access, "refresh_token": refresh})
}

func (h *Handler) WebRefresh(c *gin.Context) {
	refresh, err := c.Cookie(refreshCookie)
	if err != nil || refresh == "" {
		var req webRefreshRequest
		if bindErr := c.ShouldBindJSON(&req); bindErr == nil {
			refresh = strings.TrimSpace(req.RefreshToken)
		}
	}
	if refresh == "" {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "missing refresh token"})
		return
	}
	access, rotated, err := h.auth.Refresh(refresh)
	if err != nil {
		clearWebCookies(c)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid refresh token"})
		return
	}
	csrf := setWebCookies(c, access, rotated)
	c.JSON(http.StatusOK, gin.H{"authenticated": true, "csrf_token": csrf, "access_token": access, "refresh_token": rotated})
}

func (h *Handler) WebLogout(c *gin.Context) {
	refresh, _ := c.Cookie(refreshCookie)
	if err := h.auth.RevokeRefreshToken(refresh); err != nil {
		internalError(c, err)
		return
	}
	clearWebCookies(c)
	c.Status(http.StatusNoContent)
}

func (h *Handler) WebRevokeAll(c *gin.Context) {
	if err := h.auth.RevokeAll(c.GetInt("user_id")); err != nil {
		internalError(c, err)
		return
	}
	clearWebCookies(c)
	c.Status(http.StatusNoContent)
}

func (h *Handler) WebMe(c *gin.Context) {
	userID := c.GetInt("user_id")
	var name, email string
	if err := h.db.QueryRow(`SELECT name, email FROM users WHERE id=$1`, userID).Scan(&name, &email); err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": userID, "name": name, "email": email})
}

func (h *Handler) WebLibrary(c *gin.Context) {
	userID := c.GetInt("user_id")
	likes, err := h.likes.GetUserLikes(userID)
	if err != nil {
		internalError(c, err)
		return
	}
	playlists, err := h.playlists.ListByUser(userID)
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"likes":     likes,
		"playlists": playlists,
		"provider": gin.H{
			"id":              "youtube_music",
			"name":            "YouTube Music",
			"connected":       h.youtubeOAuthConnected(userID) || youtubeProviderConfigured(),
			"oauth_connected": h.youtubeOAuthConnected(userID),
			"oauth_available": googleOAuthConfigured(),
			"playback_ready":  youtubeProviderConfigured(),
			"status": func() string {
				if h.youtubeOAuthConnected(userID) && !youtubeProviderConfigured() {
					return "oauth_connected"
				}
				return youtubeProviderStatus()
			}(),
			"server_only": true,
		},
	})
}

func (h *Handler) WebLibraryLikes(c *gin.Context) {
	likes, err := h.likes.GetUserLikes(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, likes)
}

func (h *Handler) WebLibraryAddLike(c *gin.Context) {
	var req SongRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	like, err := h.likes.AddLike(c.GetInt("user_id"), req.toServiceInput())
	if err != nil {
		if errors.Is(err, services.ErrAlreadyLiked) {
			c.JSON(http.StatusConflict, ErrorResponse{Error: "song already liked"})
			return
		}
		internalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, like)
}

func (h *Handler) WebLibraryRemoveLike(c *gin.Context) {
	likeID, ok := parseID(c, "like_id")
	if !ok {
		return
	}
	if err := h.likes.RemoveLike(c.GetInt("user_id"), likeID); err != nil {
		if errors.Is(err, services.ErrLikeNotFound) {
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "like not found"})
			return
		}
		internalError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}

func (h *Handler) WebLibraryPlaylists(c *gin.Context) {
	playlists, err := h.playlists.ListByUser(c.GetInt("user_id"))
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusOK, playlists)
}

func (h *Handler) WebLibraryCreatePlaylist(c *gin.Context) {
	var req CreatePlaylistRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	playlist, err := h.playlists.Create(c.GetInt("user_id"), services.CreatePlaylistInput{
		Name:        req.Name,
		Description: req.Description,
	})
	if err != nil {
		internalError(c, err)
		return
	}
	c.JSON(http.StatusCreated, playlist)
}

func (h *Handler) WebLibraryAddSongToPlaylist(c *gin.Context) {
	playlistID, ok := parseID(c, "playlist_id")
	if !ok {
		return
	}
	var req SongRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, ErrorResponse{Error: err.Error()})
		return
	}
	song, err := h.playlists.AddSong(c.GetInt("user_id"), playlistID, req.toServiceInput())
	if err != nil {
		switch {
		case errors.Is(err, services.ErrPlaylistNotFound):
			c.JSON(http.StatusNotFound, ErrorResponse{Error: "playlist not found"})
		case errors.Is(err, services.ErrSongAlreadyInList):
			c.JSON(http.StatusConflict, ErrorResponse{Error: "song already in playlist"})
		default:
			internalError(c, err)
		}
		return
	}
	c.JSON(http.StatusCreated, song)
}

func youtubeProviderConfigured() bool {
	return strings.TrimSpace(os.Getenv("YOUTUBE_COOKIE_HEADER")) != "" || strings.TrimSpace(os.Getenv("YOUTUBE_AUTH_HEADER")) != ""
}

func googleOAuthConfigured() bool {
	return strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_ID")) != "" && strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_SECRET")) != ""
}

func youtubeOAuthRedirectURI(c *gin.Context) string {
	if configured := strings.TrimRight(os.Getenv("GOOGLE_OAUTH_REDIRECT_URL"), "/"); configured != "" {
		return configured
	}
	scheme := "https"
	if c.Request.TLS == nil {
		scheme = "http"
	}
	if forwarded := c.GetHeader("X-Forwarded-Proto"); forwarded != "" {
		scheme = strings.Split(forwarded, ",")[0]
	}
	return fmt.Sprintf("%s://%s/api/v2/providers/youtube/oauth/callback", scheme, c.Request.Host)
}

func publicWebAppURL() string {
	if url := strings.TrimRight(os.Getenv("PUBLIC_WEB_APP_URL"), "/"); url != "" {
		return url
	}
	return "https://musicglass-pwa-test-20260616135652.netlify.app"
}

func youtubeProviderStatus() string {
	if youtubeProviderConfigured() {
		return "playback_ready"
	}
	if googleOAuthConfigured() {
		return "oauth_available"
	}
	return "server_setup_required"
}

func (h *Handler) youtubeOAuthConnected(userID int) bool {
	var exists bool
	err := h.db.QueryRow(`SELECT EXISTS(SELECT 1 FROM provider_accounts WHERE user_id=$1 AND provider='youtube_music')`, userID).Scan(&exists)
	return err == nil && exists
}

func (h *Handler) WebYouTubeProviderStatus(c *gin.Context) {
	userID := c.GetInt("user_id")
	oauthConnected := userID > 0 && h.youtubeOAuthConnected(userID)
	status := youtubeProviderStatus()
	if oauthConnected && !youtubeProviderConfigured() {
		status = "oauth_connected"
	}
	c.JSON(http.StatusOK, gin.H{
		"id":              "youtube_music",
		"name":            "YouTube Music",
		"connected":       oauthConnected || youtubeProviderConfigured(),
		"oauth_connected": oauthConnected,
		"oauth_available": googleOAuthConfigured(),
		"playback_ready":  youtubeProviderConfigured(),
		"status":          status,
		"server_only":     true,
	})
}

func (h *Handler) WebYouTubeProviderConnect(c *gin.Context) {
	userID := c.GetInt("user_id")
	if youtubeProviderConfigured() {
		c.JSON(http.StatusOK, gin.H{"connected": true, "oauth_connected": h.youtubeOAuthConnected(userID), "oauth_available": googleOAuthConfigured(), "playback_ready": true, "status": "playback_ready"})
		return
	}
	if h.youtubeOAuthConnected(userID) {
		c.JSON(http.StatusOK, gin.H{
			"connected":       true,
			"oauth_connected": true,
			"oauth_available": googleOAuthConfigured(),
			"playback_ready":  false,
			"status":          "oauth_connected",
			"message":         "Compte Google lié. La lecture YouTube Music privée nécessite encore une résolution audio autorisée côté serveur.",
		})
		return
	}
	if googleOAuthConfigured() {
		stateBytes := make([]byte, 32)
		if _, err := rand.Read(stateBytes); err != nil {
			internalError(c, err)
			return
		}
		state := base64.RawURLEncoding.EncodeToString(stateBytes)
		_, err := h.db.Exec(
			`INSERT INTO provider_oauth_states(state, user_id, provider, expires_at) VALUES($1,$2,'youtube_music',NOW()+INTERVAL '10 minutes')`,
			state,
			userID,
		)
		if err != nil {
			internalError(c, err)
			return
		}
		params := fmt.Sprintf(
			"client_id=%s&redirect_uri=%s&response_type=code&scope=%s&access_type=offline&prompt=consent&state=%s",
			url.QueryEscape(os.Getenv("GOOGLE_CLIENT_ID")),
			url.QueryEscape(youtubeOAuthRedirectURI(c)),
			url.QueryEscape("openid email profile https://www.googleapis.com/auth/youtube.readonly"),
			url.QueryEscape(state),
		)
		c.JSON(http.StatusOK, gin.H{
			"connected":       false,
			"oauth_connected": false,
			"oauth_available": true,
			"playback_ready":  false,
			"status":          "oauth_required",
			"auth_url":        "https://accounts.google.com/o/oauth2/v2/auth?" + params,
			"message":         "Ouvrez Google pour lier le compte YouTube Music.",
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"connected":       false,
		"oauth_connected": false,
		"oauth_available": false,
		"playback_ready":  false,
		"status":          "server_setup_required",
		"message":         "Configurez GOOGLE_CLIENT_ID et GOOGLE_CLIENT_SECRET pour ouvrir la connexion Google. Pour la lecture privée YouTube Music, le backend a aussi besoin d'une méthode serveur autorisée pour résoudre les flux.",
	})
}

func (h *Handler) WebYouTubeOAuthCallback(c *gin.Context) {
	state := c.Query("state")
	code := c.Query("code")
	if state == "" || code == "" {
		c.Data(http.StatusBadRequest, "text/html; charset=utf-8", []byte(oauthCallbackHTML("error", "Paramètres Google manquants.")))
		return
	}
	var userID int
	var expiresAt time.Time
	err := h.db.QueryRow(
		`SELECT user_id, expires_at FROM provider_oauth_states WHERE state=$1 AND provider='youtube_music'`,
		state,
	).Scan(&userID, &expiresAt)
	if err != nil || time.Now().After(expiresAt) {
		c.Data(http.StatusBadRequest, "text/html; charset=utf-8", []byte(oauthCallbackHTML("error", "Session de connexion expirée.")))
		return
	}
	_, _ = h.db.Exec(`DELETE FROM provider_oauth_states WHERE state=$1`, state)

	token, err := exchangeGoogleOAuthCode(c.Request.Context(), code, youtubeOAuthRedirectURI(c))
	if err != nil {
		log.Printf("[YouTubeOAuth] token exchange failed: %v", err)
		c.Data(http.StatusBadGateway, "text/html; charset=utf-8", []byte(oauthCallbackHTML("error", "Google a refusé l'échange du code.")))
		return
	}
	profile, _ := fetchGoogleUserInfo(c.Request.Context(), token.AccessToken)
	_, err = h.db.Exec(
		`INSERT INTO provider_accounts(user_id, provider, external_id, email, display_name, access_token, refresh_token, scopes, expires_at, updated_at)
		 VALUES($1,'youtube_music',$2,$3,$4,$5,$6,$7,$8,NOW())
		 ON CONFLICT(user_id, provider) DO UPDATE SET
		   external_id=EXCLUDED.external_id,
		   email=EXCLUDED.email,
		   display_name=EXCLUDED.display_name,
		   access_token=EXCLUDED.access_token,
		   refresh_token=COALESCE(NULLIF(EXCLUDED.refresh_token,''), provider_accounts.refresh_token),
		   scopes=EXCLUDED.scopes,
		   expires_at=EXCLUDED.expires_at,
		   updated_at=NOW()`,
		userID,
		profile.Sub,
		profile.Email,
		profile.Name,
		token.AccessToken,
		token.RefreshToken,
		token.Scope,
		time.Now().Add(time.Duration(token.ExpiresIn)*time.Second),
	)
	if err != nil {
		internalHTML := oauthCallbackHTML("error", "Compte lié côté Google, mais sauvegarde backend impossible.")
		c.Data(http.StatusInternalServerError, "text/html; charset=utf-8", []byte(internalHTML))
		return
	}
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(oauthCallbackHTML("success", "Compte Google lié à MusicGlass.")))
}

type googleTokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int    `json:"expires_in"`
	Scope        string `json:"scope"`
	TokenType    string `json:"token_type"`
}

type googleUserInfo struct {
	Sub   string `json:"sub"`
	Email string `json:"email"`
	Name  string `json:"name"`
}

func exchangeGoogleOAuthCode(ctx context.Context, code, redirectURI string) (googleTokenResponse, error) {
	values := url.Values{}
	values.Set("code", code)
	values.Set("client_id", os.Getenv("GOOGLE_CLIENT_ID"))
	values.Set("client_secret", os.Getenv("GOOGLE_CLIENT_SECRET"))
	values.Set("redirect_uri", redirectURI)
	values.Set("grant_type", "authorization_code")
	form := values.Encode()
	req, err := http.NewRequest(http.MethodPost, "https://oauth2.googleapis.com/token", bytes.NewBufferString(form))
	if err != nil {
		return googleTokenResponse{}, err
	}
	req = req.WithContext(ctx)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return googleTokenResponse{}, err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return googleTokenResponse{}, fmt.Errorf("google token status %d: %s", res.StatusCode, string(body))
	}
	var token googleTokenResponse
	if err := json.Unmarshal(body, &token); err != nil {
		return googleTokenResponse{}, err
	}
	if token.AccessToken == "" {
		return googleTokenResponse{}, errors.New("missing google access token")
	}
	return token, nil
}

func fetchGoogleUserInfo(ctx context.Context, accessToken string) (googleUserInfo, error) {
	req, err := http.NewRequest(http.MethodGet, "https://openidconnect.googleapis.com/v1/userinfo", nil)
	if err != nil {
		return googleUserInfo{}, err
	}
	req = req.WithContext(ctx)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return googleUserInfo{}, err
	}
	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return googleUserInfo{}, fmt.Errorf("google userinfo status %d", res.StatusCode)
	}
	var profile googleUserInfo
	if err := json.Unmarshal(body, &profile); err != nil {
		return googleUserInfo{}, err
	}
	return profile, nil
}

func oauthCallbackHTML(status, message string) string {
	encodedStatus, _ := json.Marshal(status)
	encodedMessage, _ := json.Marshal(message)
	appURL, _ := json.Marshal(publicWebAppURL() + "/library")
	return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MusicGlass</title><style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#09080c;color:#fff;font-family:system-ui,-apple-system,BlinkMacSystemFont,sans-serif}.card{max-width:420px;margin:24px;padding:28px;border-radius:28px;background:linear-gradient(145deg,rgba(240,82,125,.24),rgba(255,154,97,.12));border:1px solid rgba(255,255,255,.12)}h1{margin:0 0 10px;font-size:28px}p{color:rgba(255,255,255,.72);line-height:1.5}a{color:#fff;font-weight:800}</style></head><body><main class="card"><h1>MusicGlass</h1><p>` + message + `</p><p><a href="` + publicWebAppURL() + `/library">Revenir à l’app</a></p></main><script>const payload={type:"musicglass:youtube-oauth",status:` + string(encodedStatus) + `,message:` + string(encodedMessage) + `};try{if(window.opener){window.opener.postMessage(payload,` + string(appURL) + `.replace(/\/library$/,''));setTimeout(()=>window.close(),650)}}catch(e){}try{localStorage.setItem("musicglass-youtube-oauth-result",JSON.stringify({...payload,at:Date.now()}))}catch(e){}</script></body></html>`
}

func (h *Handler) WebCatalogStatus(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"provider": "youtube", "status": "active", "browserDirectAccess": false})
}

func (h *Handler) WebCatalogHome(c *gin.Context) {
	res, err := h.youtube.Home(h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

func (h *Handler) WebCatalogPlaylist(c *gin.Context) {
	id := c.Param("id")
	if id == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "playlist id is required"})
		return
	}

	visitorData := h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA"))
	res, err := h.youtube.Playlist(id, visitorData)
	if err != nil {
		internalError(c, err)
		return
	}
	playlist := canonicalWebPlaylist(res)
	ctx, cancel := context.WithTimeout(c.Request.Context(), playlistArtworkEnrichmentTimeout)
	defer cancel()
	playlist.Tracks = enrichPlaylistArtwork(ctx, playlist.Tracks, func(query string) (map[string]interface{}, error) {
		return h.youtube.Search(query, "", visitorData)
	}, sharedPlaylistArtworkCache, playlistArtworkSearchConcurrency)
	playlist.Tracks = replaceVideoArtworkFallbacks(playlist.Tracks, playlist.Artwork)
	c.JSON(http.StatusOK, playlist)
}

func (h *Handler) WebCatalogSearch(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing query"})
		return
	}
	res, err := h.youtube.Search(query, "", h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, res)
}

func (h *Handler) WebCatalogRadio(c *gin.Context) {
	trackID := c.Query("track_id")
	title := c.Query("title")
	artist := c.Query("artist")
	query := strings.TrimSpace(title + " " + artist)
	if query == "" && trackID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "missing radio seed"})
		return
	}
	if query == "" {
		query = trackID
	}

	visitorData := h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA"))
	res, err := h.youtube.Related(trackID, visitorData)
	tracks := []webTrack{}
	source := "youtube_music_next"
	if err == nil {
		tracks = extractWebTracks(res, trackID)
	}
	if len(tracks) == 0 {
		source = "search_fallback"
		fallbackQuery := strings.TrimSpace(artist)
		if fallbackQuery == "" {
			fallbackQuery = query
		}
		res, err = h.youtube.Search(fallbackQuery, "", visitorData)
		if err == nil {
			tracks = filterRadioFallbackTracks(extractWebTracks(res, trackID), artist)
		}
	}
	if err != nil {
		c.JSON(http.StatusOK, gin.H{
			"seed":   webTrack{ID: trackID, Title: title, Artist: artist, Accent: "#263443"},
			"tracks": []webTrack{},
			"source": "search_fallback",
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"seed":   webTrack{ID: trackID, Title: title, Artist: artist, Accent: "#263443"},
		"tracks": tracks,
		"source": source,
	})
}

// A text search is only an emergency fallback. Restrict it to the seed artist
// so an ambiguous song title cannot turn the queue into an unrelated topic mix.
func filterRadioFallbackTracks(tracks []webTrack, seedArtist string) []webTrack {
	seedTokens := artistTokens(seedArtist)
	if len(seedTokens) == 0 {
		return tracks
	}

	filtered := make([]webTrack, 0, len(tracks))
	for _, track := range tracks {
		candidateTokens := artistTokens(track.Artist)
		matched := false
		for artist := range seedTokens {
			if candidateTokens[artist] {
				matched = true
				break
			}
		}
		if matched {
			filtered = append(filtered, track)
		}
	}
	return filtered
}

func (h *Handler) WebMediaResolve(c *gin.Context) {
	trackID := c.Param("track_id")
	title := c.Query("title")
	artist := c.Query("artist")
	start := time.Now()
	resolvedID, entry, cached, err := h.resolvePlayableStream(trackID, title, artist)
	if err != nil {
		log.Printf("[WebMediaResolve] track_id=%s failed resolve_ms=%d err=%v", trackID, time.Since(start).Milliseconds(), err)
		if errors.Is(err, errYouTubeCredentialsRequired) {
			c.JSON(http.StatusPreconditionRequired, gin.H{
				"error":   "provider_credentials_required",
				"message": "Connexion YouTube Music serveur requise: configurez YOUTUBE_COOKIE_HEADER côté backend.",
			})
			return
		}
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to resolve stream"})
		return
	}
	log.Printf("[WebMediaResolve] track_id=%s resolved_id=%s cached=%t resolve_ms=%d", trackID, resolvedID, cached, time.Since(start).Milliseconds())
	c.JSON(http.StatusOK, gin.H{
		"stream_url":         "/api/v2/media/stream/" + resolvedID,
		"resolved_track_id":  resolvedID,
		"cached":             cached,
		"expires_in_seconds": int(time.Until(entry.ExpiresAt).Seconds()),
		"upstream_mime_type": entry.MimeType,
		"resolver":           entry.Source,
		"duration_seconds":   entry.DurationSeconds,
	})
}

func (h *Handler) resolvePlayableStream(trackID, title, artist string) (string, streamCacheEntry, bool, error) {
	entry, cached, err := resolveStreamURL(trackID)
	if err == nil {
		return trackID, entry, cached, nil
	}

	query := strings.TrimSpace(title + " " + artist)
	if query == "" || query == trackID {
		return "", streamCacheEntry{}, false, err
	}

	res, searchErr := h.youtube.Search(query, "", h.youtube.CachedVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA")))
	if searchErr != nil {
		return "", streamCacheEntry{}, false, err
	}
	tracks := extractWebTracks(res, trackID)
	for _, candidate := range tracks {
		if candidate.ID == "" || candidate.ID == trackID || !isPlaybackFallbackMatch(candidate.Title, candidate.Artist, title, artist) {
			continue
		}
		entry, cached, candidateErr := resolveStreamURL(candidate.ID)
		if candidateErr == nil {
			return candidate.ID, entry, cached, nil
		}
	}
	return "", streamCacheEntry{}, false, err
}

func (h *Handler) WebMediaStream(c *gin.Context) {
	trackID := c.Param("track_id")
	start := time.Now()
	entry, cached, err := resolveStreamURL(trackID)
	if err != nil {
		log.Printf("[WebMediaStream] track_id=%s failed resolve_ms=%d err=%v", trackID, time.Since(start).Milliseconds(), err)
		if errors.Is(err, errYouTubeCredentialsRequired) {
			c.JSON(http.StatusPreconditionRequired, gin.H{
				"error":   "provider_credentials_required",
				"message": "Connexion YouTube Music serveur requise: configurez YOUTUBE_COOKIE_HEADER côté backend.",
			})
			return
		}
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to extract stream url"})
		return
	}

	upResp, err := requestAudioUpstream(c.Request.Context(), entry.URL, c.GetHeader("Range"))
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "upstream request failed"})
		return
	}
	if upResp.StatusCode == http.StatusForbidden || upResp.StatusCode == http.StatusGone || upResp.StatusCode == http.StatusNotFound {
		upResp.Body.Close()
		forgetStreamURL(trackID)
		freshEntry, _, resolveErr := resolveStreamURL(trackID)
		if resolveErr == nil {
			entry = freshEntry
			cached = false
			upResp, err = requestAudioUpstream(c.Request.Context(), entry.URL, c.GetHeader("Range"))
		}
		if resolveErr != nil || err != nil {
			c.JSON(http.StatusBadGateway, gin.H{"error": "upstream refresh failed"})
			return
		}
	}
	defer upResp.Body.Close()
	firstByteMs := time.Since(start).Milliseconds()
	log.Printf("[WebMediaStream] track_id=%s cached=%t status=%d first_byte_ms=%d", trackID, cached, upResp.StatusCode, firstByteMs)

	// Relay relevant headers from the upstream response.
	if ct := upResp.Header.Get("Content-Type"); ct != "" {
		c.Header("Content-Type", ct)
	}
	if cl := upResp.Header.Get("Content-Length"); cl != "" {
		c.Header("Content-Length", cl)
	}
	if acceptRanges := upResp.Header.Get("Accept-Ranges"); acceptRanges != "" {
		c.Header("Accept-Ranges", acceptRanges)
	}
	// Range responses must never be reused for a different byte interval. In
	// particular, iOS frequently closes and reopens the media request on pause.
	c.Header("Cache-Control", "private, no-store, no-transform")
	c.Header("X-Content-Type-Options", "nosniff")
	if cr := upResp.Header.Get("Content-Range"); cr != "" {
		c.Header("Content-Range", cr)
	}

	// Use the upstream status code (200 for full body, 206 for partial content).
	c.Status(upResp.StatusCode)

	// Stream the audio bytes to the client.
	buffer := make([]byte, 64*1024)
	_, _ = io.CopyBuffer(c.Writer, upResp.Body, buffer)
}

var errYouTubeCredentialsRequired = errors.New("youtube provider credentials required")

var streamYouTubeService = services.NewYouTubeService()

var mediaHTTPClient = &http.Client{
	Transport: &http.Transport{
		MaxIdleConns:          64,
		MaxIdleConnsPerHost:   24,
		IdleConnTimeout:       90 * time.Second,
		ResponseHeaderTimeout: 15 * time.Second,
	},
}

var artworkHTTPClient = &http.Client{
	Timeout: 12 * time.Second,
	CheckRedirect: func(req *http.Request, via []*http.Request) error {
		if len(via) >= 3 || !isAllowedArtworkURL(req.URL) {
			return http.ErrUseLastResponse
		}
		return nil
	},
}

func isAllowedArtworkURL(value *url.URL) bool {
	if value == nil || value.Scheme != "https" {
		return false
	}
	host := strings.ToLower(value.Hostname())
	for _, allowed := range []string{"googleusercontent.com", "ggpht.com", "ytimg.com", "i.scdn.co"} {
		if host == allowed || strings.HasSuffix(host, "."+allowed) {
			return true
		}
	}
	return false
}

func (h *Handler) WebMediaArtwork(c *gin.Context) {
	artworkURL, err := url.Parse(c.Query("url"))
	if err != nil || !isAllowedArtworkURL(artworkURL) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid artwork URL"})
		return
	}

	request, err := http.NewRequestWithContext(c.Request.Context(), http.MethodGet, artworkURL.String(), nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid artwork request"})
		return
	}
	request.Header.Set("Accept", "image/avif,image/webp,image/jpeg,image/png,image/*")
	request.Header.Set("User-Agent", "MusicGlass/1.0")

	response, err := artworkHTTPClient.Do(request)
	if err != nil {
		c.JSON(http.StatusBadGateway, gin.H{"error": "failed to fetch artwork"})
		return
	}
	defer response.Body.Close()
	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		c.JSON(http.StatusBadGateway, gin.H{"error": "artwork provider rejected the request"})
		return
	}
	contentType := response.Header.Get("Content-Type")
	if !strings.HasPrefix(contentType, "image/") {
		c.JSON(http.StatusBadGateway, gin.H{"error": "invalid artwork response"})
		return
	}

	c.Header("Content-Type", contentType)
	c.Header("Cache-Control", "public, max-age=86400, immutable")
	c.Header("X-Content-Type-Options", "nosniff")
	c.Status(http.StatusOK)
	_, _ = io.Copy(c.Writer, io.LimitReader(response.Body, 10<<20))
}

func requestAudioUpstream(ctx context.Context, streamURL, rangeHeader string) (*http.Response, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, streamURL, nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")
	if rangeHeader != "" {
		request.Header.Set("Range", rangeHeader)
	}
	return mediaHTTPClient.Do(request)
}

func resolveStreamURL(trackID string) (streamCacheEntry, bool, error) {
	now := time.Now()
	streamCache.RLock()
	if entry, ok := streamCache.values[trackID]; ok && entry.ExpiresAt.After(now.Add(2*time.Minute)) {
		streamCache.RUnlock()
		return entry, true, nil
	}
	streamCache.RUnlock()

	ytService := streamYouTubeService
	visitorData := ytService.BootstrapVisitorData(os.Getenv("YOUTUBE_VISITOR_DATA"))
	cookieHeader := os.Getenv("YOUTUBE_COOKIE_HEADER")
	authHeader := os.Getenv("YOUTUBE_AUTH_HEADER")
	if strings.TrimSpace(cookieHeader) != "" {
		if authHeader == "" {
			authHeader = youtubeSAPISIDHash(cookieHeader)
		}
	}
	if player, playerErr := ytService.Player(trackID, visitorData, cookieHeader, authHeader); playerErr == nil {
		if audioURL, extractErr := ytService.ExtractAudioURL(player); extractErr == nil && audioURL != "" {
			entry := streamCacheEntry{
				URL:             audioURL,
				MimeType:        "audio/mp4",
				Source:          "innertube",
				DurationSeconds: positiveInteger(stringAt(player, "videoDetails", "lengthSeconds")),
				ExpiresAt:       now.Add(45 * time.Minute),
			}
			streamCache.Lock()
			streamCache.values[trackID] = entry
			streamCache.Unlock()
			return entry, false, nil
		}
	}

	client := youtube.Client{}
	video, err := client.GetVideo(trackID)
	if err != nil {
		return streamCacheEntry{}, false, err
	}
	formats := video.Formats.WithAudioChannels()
	if len(formats) == 0 {
		return streamCacheEntry{}, false, errors.New("no audio formats found")
	}
	formats.Sort()
	bestFormat := formats[0]
	for _, format := range formats {
		if strings.HasPrefix(format.MimeType, "audio/") {
			bestFormat = format
			break
		}
	}
	audioURL, err := client.GetStreamURL(video, &bestFormat)
	if err != nil || audioURL == "" {
		return streamCacheEntry{}, false, errors.New("failed to extract stream url")
	}
	entry := streamCacheEntry{
		URL:             audioURL,
		MimeType:        bestFormat.MimeType,
		Source:          "youtube_fallback",
		DurationSeconds: int(video.Duration.Round(time.Second) / time.Second),
		ExpiresAt:       now.Add(45 * time.Minute),
	}
	streamCache.Lock()
	streamCache.values[trackID] = entry
	streamCache.Unlock()
	return entry, false, nil
}

func youtubeSAPISIDHash(cookieHeader string) string {
	sapisid := ""
	for _, part := range strings.Split(cookieHeader, ";") {
		trimmed := strings.TrimSpace(part)
		if strings.HasPrefix(trimmed, "SAPISID=") {
			sapisid = strings.TrimPrefix(trimmed, "SAPISID=")
			break
		}
		if strings.HasPrefix(trimmed, "__Secure-3PAPISID=") {
			sapisid = strings.TrimPrefix(trimmed, "__Secure-3PAPISID=")
			break
		}
	}
	if sapisid == "" {
		return ""
	}
	timestamp := time.Now().Unix()
	payload := []byte(fmt.Sprintf("%d %s https://music.youtube.com", timestamp, sapisid))
	sum := sha1.Sum(payload)
	return fmt.Sprintf("SAPISIDHASH %d_%s", timestamp, hex.EncodeToString(sum[:]))
}

func forgetStreamURL(trackID string) {
	streamCache.Lock()
	delete(streamCache.values, trackID)
	streamCache.Unlock()
}

func isPlaybackFallbackMatch(candidateTitle, candidateArtist, originalTitle, originalArtist string) bool {
	candidateStem := titleStem(candidateTitle)
	originalStem := titleStem(originalTitle)
	if candidateStem == "" || originalStem == "" {
		return false
	}
	titleMatches := candidateStem == originalStem || strings.Contains(candidateStem, originalStem) || strings.Contains(originalStem, candidateStem)
	if !titleMatches {
		return false
	}
	candidateTokens := artistTokens(candidateArtist)
	originalTokens := artistTokens(originalArtist)
	if len(candidateTokens) == 0 || len(originalTokens) == 0 {
		return true
	}
	for token := range candidateTokens {
		if originalTokens[token] {
			return true
		}
	}
	return false
}

func titleStem(value string) string {
	value = strings.ToLower(value)
	cutIndexes := []int{
		strings.Index(value, "("),
		strings.Index(value, "["),
	}
	cutAt := -1
	for _, index := range cutIndexes {
		if index > 0 && (cutAt == -1 || index < cutAt) {
			cutAt = index
		}
	}
	if cutAt > 0 {
		value = value[:cutAt]
	}
	var builder strings.Builder
	lastSpace := false
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			builder.WriteRune(r)
			lastSpace = false
			continue
		}
		if !lastSpace {
			builder.WriteRune(' ')
			lastSpace = true
		}
	}
	return strings.TrimSpace(builder.String())
}

func artistTokens(value string) map[string]bool {
	replacer := strings.NewReplacer(" feat. ", ",", " ft. ", ",", " avec ", ",", "&", ",", "•", ",", "·", ",", "/", ",", ";", ",", "|", ",")
	parts := strings.Split(replacer.Replace(strings.ToLower(value)), ",")
	tokens := map[string]bool{}
	for _, part := range parts {
		token := strings.TrimSpace(part)
		if token != "" {
			tokens[token] = true
		}
	}
	return tokens
}

func extractWebTracks(root map[string]interface{}, seedID string) []webTrack {
	renderers := findMapsNamed(root, "musicResponsiveListItemRenderer")
	const trackLimit = 36
	tracks := make([]webTrack, 0, trackLimit)
	seen := map[string]bool{}
	for _, renderer := range renderers {
		id := stringAt(renderer, "playlistItemData", "videoId")
		if id == "" {
			id = stringAt(renderer, "navigationItemData", "videoId")
		}
		if id == "" || id == seedID || seen[id] {
			continue
		}
		title := textFrom(renderer["title"])
		if title == "" {
			title = textAt(renderer, "flexColumns", "0", "musicResponsiveListItemFlexColumnRenderer", "text")
		}
		metadata := responsiveFlexColumnText(renderer, 1)
		artist := musicPageRunText(metadata, "MUSIC_PAGE_TYPE_ARTIST")
		album := musicPageRunText(metadata, "MUSIC_PAGE_TYPE_ALBUM")
		videoType := musicVideoType(renderer)
		if title == "" || !isReliableArtist(artist) || isRejectedMusicCandidate(title, textFrom(metadata)) ||
			(videoType != "MUSIC_VIDEO_TYPE_ATV" && videoType != "MUSIC_VIDEO_TYPE_OMV") {
			continue
		}
		seen[id] = true
		tracks = append(tracks, webTrack{
			ID:       id,
			Title:    title,
			Artist:   artist,
			Album:    album,
			Artwork:  thumbnailFrom(renderer, id),
			Duration: 0,
			Accent:   "#263443",
		})
		if len(tracks) >= trackLimit {
			break
		}
	}
	panelRenderers := findMapsNamed(root, "playlistPanelVideoRenderer")
	for _, renderer := range panelRenderers {
		if len(tracks) >= trackLimit {
			break
		}
		id, _ := renderer["videoId"].(string)
		if id == "" || id == seedID || seen[id] {
			continue
		}
		title := textFrom(renderer["title"])
		byline := renderer["shortBylineText"]
		artist := musicPageRunText(byline, "MUSIC_PAGE_TYPE_ARTIST")
		if artist == "" {
			artist = cleanArtistLabel(textFrom(byline))
		}
		if artist == "" {
			byline = renderer["longBylineText"]
			artist = musicPageRunText(byline, "MUSIC_PAGE_TYPE_ARTIST")
			if artist == "" {
				artist = cleanArtistLabel(textFrom(byline))
			}
		}
		if title == "" || !isReliableArtist(artist) || isRejectedPanelCandidate(title, textFrom(byline)) {
			continue
		}
		seen[id] = true
		tracks = append(tracks, webTrack{
			ID:       id,
			Title:    title,
			Artist:   artist,
			Artwork:  thumbnailFrom(renderer, id),
			Duration: durationSeconds(textFrom(renderer["lengthText"])),
			Accent:   "#263443",
		})
	}
	return tracks
}

func cleanArtistLabel(value string) string {
	parts := strings.Split(value, "•")
	artist := strings.TrimSpace(parts[0])
	if !isReliableArtist(artist) {
		return ""
	}
	return artist
}

func musicPageRunText(value interface{}, expectedPageType string) string {
	asMap, ok := value.(map[string]interface{})
	if !ok {
		return ""
	}
	runs, ok := asMap["runs"].([]interface{})
	if !ok {
		return ""
	}
	values := make([]string, 0, 2)
	for _, value := range runs {
		run, ok := value.(map[string]interface{})
		if !ok {
			continue
		}
		pageType := stringAt(run, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs", "browseEndpointContextMusicConfig", "pageType")
		text, _ := run["text"].(string)
		if pageType == expectedPageType && strings.TrimSpace(text) != "" {
			values = append(values, strings.TrimSpace(text))
		}
	}
	return strings.Join(values, ", ")
}

func responsiveFlexColumnText(renderer map[string]interface{}, index int) interface{} {
	columns, ok := renderer["flexColumns"].([]interface{})
	if !ok || index < 0 || index >= len(columns) {
		return nil
	}
	column, ok := columns[index].(map[string]interface{})
	if !ok {
		return nil
	}
	flexColumn, ok := column["musicResponsiveListItemFlexColumnRenderer"].(map[string]interface{})
	if !ok {
		return nil
	}
	return flexColumn["text"]
}

func musicVideoType(renderer map[string]interface{}) string {
	var found string
	var walk func(interface{})
	walk = func(value interface{}) {
		if found != "" {
			return
		}
		switch typed := value.(type) {
		case map[string]interface{}:
			if videoType, ok := typed["musicVideoType"].(string); ok {
				found = videoType
				return
			}
			for _, child := range typed {
				walk(child)
			}
		case []interface{}:
			for _, child := range typed {
				walk(child)
			}
		}
	}
	walk(renderer)
	return found
}

func isReliableArtist(value string) bool {
	artist := strings.TrimSpace(value)
	lower := strings.ToLower(artist)
	if artist == "" || durationSeconds(artist) > 0 || strings.Contains(lower, " vue") || strings.Contains(lower, " view") {
		return false
	}
	switch lower {
	case "titre", "song", "vidéo", "video", "profil", "profile", "playlist", "artiste", "artist",
		"podcast", "épisode", "episode", "paroles", "lyrics", "inconnu", "unknown":
		return false
	default:
		return true
	}
}

func isRejectedMusicCandidate(values ...string) bool {
	return hasRejectedMarker(values, []string{
		"podcast", "épisode", "episode", "livestream", "live", "paroles", "lyrics", "karaoké", "karaoke",
		"réaction", "reaction", "interview", "entretien", "1h",
	})
}

func isRejectedPanelCandidate(values ...string) bool {
	return hasRejectedMarker(values, []string{"podcast", "épisode", "episode", "livestream", "live"})
}

func hasRejectedMarker(values []string, rejected []string) bool {
	text := strings.ToLower(strings.Join(values, " "))
	if strings.Contains(text, "live stream") || strings.Contains(text, "en direct") ||
		strings.Contains(text, "1 heure") || strings.Contains(text, "1 hour") {
		return true
	}
	words := strings.FieldsFunc(text, func(char rune) bool {
		return !((char >= 'a' && char <= 'z') || (char >= '0' && char <= '9') || char >= 128)
	})
	for _, word := range words {
		for _, marker := range rejected {
			if word == marker {
				return true
			}
		}
	}
	return false
}

func durationSeconds(value string) int {
	parts := strings.Split(strings.TrimSpace(value), ":")
	if len(parts) < 2 || len(parts) > 3 {
		return 0
	}
	total := 0
	for _, part := range parts {
		number, err := strconv.Atoi(part)
		if err != nil {
			return 0
		}
		total = total*60 + number
	}
	return total
}

func positiveInteger(value string) int {
	number, err := strconv.Atoi(strings.TrimSpace(value))
	if err != nil || number <= 0 {
		return 0
	}
	return number
}

func findMapsNamed(root interface{}, name string) []map[string]interface{} {
	var out []map[string]interface{}
	var walk func(interface{})
	walk = func(value interface{}) {
		switch typed := value.(type) {
		case map[string]interface{}:
			for key, child := range typed {
				if key == name {
					if asMap, ok := child.(map[string]interface{}); ok {
						out = append(out, asMap)
					}
					continue
				}
				walk(child)
			}
		case []interface{}:
			for _, child := range typed {
				walk(child)
			}
		}
	}
	walk(root)
	return out
}

func textAt(root map[string]interface{}, path ...string) string {
	current := interface{}(root)
	for _, key := range path {
		if arr, ok := current.([]interface{}); ok {
			index, err := strconv.Atoi(key)
			if err == nil && index >= 0 && index < len(arr) {
				current = arr[index]
				continue
			}
			return ""
		}
		asMap, ok := current.(map[string]interface{})
		if !ok {
			return ""
		}
		current = asMap[key]
	}
	return textFrom(current)
}

func textFrom(value interface{}) string {
	asMap, ok := value.(map[string]interface{})
	if !ok {
		return ""
	}
	if simple, ok := asMap["simpleText"].(string); ok {
		return simple
	}
	runs, ok := asMap["runs"].([]interface{})
	if !ok {
		return ""
	}
	parts := make([]string, 0, len(runs))
	for _, run := range runs {
		if runMap, ok := run.(map[string]interface{}); ok {
			if text, ok := runMap["text"].(string); ok {
				parts = append(parts, text)
			}
		}
	}
	return strings.Join(parts, "")
}

func stringAt(root map[string]interface{}, path ...string) string {
	current := interface{}(root)
	for _, key := range path {
		asMap, ok := current.(map[string]interface{})
		if !ok {
			return ""
		}
		current = asMap[key]
	}
	if value, ok := current.(string); ok {
		return value
	}
	return ""
}

type artworkCandidate struct {
	url            string
	width          int
	height         int
	sourcePriority int
}

var artworkSizePattern = regexp.MustCompile(`=w(\d+)-h(\d+)`)

func thumbnailFrom(renderer map[string]interface{}, videoID string) string {
	candidates := thumbnailCandidatesFrom(renderer)
	if len(candidates) > 0 {
		best := candidates[0]
		bestScore := artworkScore(best)
		for _, candidate := range candidates[1:] {
			if score := artworkScore(candidate); score > bestScore {
				best, bestScore = candidate, score
			}
		}
		return best.url
	}
	if len(videoID) == 11 {
		return "https://i.ytimg.com/vi/" + videoID + "/hq720.jpg"
	}
	return ""
}

func thumbnailCandidatesFrom(renderer map[string]interface{}) []artworkCandidate {
	paths := []struct {
		value    interface{}
		priority int
	}{
		{valueAt(renderer, "thumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"), 400},
		{valueAt(renderer, "thumbnailRenderer", "musicThumbnailRenderer", "thumbnail", "thumbnails"), 400},
		{valueAt(renderer, "thumbnail", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"), 380},
		{valueAt(renderer, "thumbnailRenderer", "croppedSquareThumbnailRenderer", "thumbnail", "thumbnails"), 380},
		{valueAt(renderer, "foregroundThumbnail", "musicThumbnailRenderer", "thumbnail", "thumbnails"), 360},
		{valueAt(renderer, "thumbnail", "thumbnails"), 100},
		{valueAt(renderer, "thumbnailRenderer", "thumbnail", "thumbnails"), 100},
	}
	candidates := make([]artworkCandidate, 0, 8)
	for _, path := range paths {
		thumbs, ok := path.value.([]interface{})
		if !ok {
			continue
		}
		for _, value := range thumbs {
			thumb, ok := value.(map[string]interface{})
			if !ok {
				continue
			}
			artworkURL, _ := thumb["url"].(string)
			if strings.HasPrefix(artworkURL, "//") {
				artworkURL = "https:" + artworkURL
			}
			if artworkURL == "" {
				continue
			}
			width, height := thumbnailDimensions(thumb, artworkURL)
			candidates = append(candidates, artworkCandidate{artworkURL, width, height, path.priority})
		}
	}
	return candidates
}

func thumbnailDimensions(thumb map[string]interface{}, artworkURL string) (int, int) {
	width, height := integerValue(thumb["width"]), integerValue(thumb["height"])
	if width > 0 && height > 0 {
		return width, height
	}
	if matches := artworkSizePattern.FindStringSubmatch(artworkURL); len(matches) == 3 {
		return positiveInteger(matches[1]), positiveInteger(matches[2])
	}
	videoSizes := map[string][2]int{
		"maxresdefault.jpg": {1280, 720},
		"hq720.jpg":         {1280, 720},
		"sddefault.jpg":     {640, 480},
		"hqdefault.jpg":     {480, 360},
		"mqdefault.jpg":     {320, 180},
		"default.jpg":       {120, 90},
	}
	for suffix, dimensions := range videoSizes {
		if strings.Contains(artworkURL, "/"+suffix) {
			return dimensions[0], dimensions[1]
		}
	}
	return width, height
}

func integerValue(value interface{}) int {
	switch typed := value.(type) {
	case int:
		return typed
	case float64:
		return int(typed)
	case json.Number:
		result, _ := strconv.Atoi(typed.String())
		return result
	case string:
		return positiveInteger(typed)
	default:
		return 0
	}
}

func artworkScore(candidate artworkCandidate) float64 {
	score := float64(candidate.sourcePriority * 100)
	if candidate.width > 0 && candidate.height > 0 {
		ratio := float64(candidate.width) / float64(candidate.height)
		delta := ratio - 1
		if delta < 0 {
			delta = -delta
		}
		switch {
		case delta <= 0.08:
			score += 1_000_000
		case delta <= 0.2:
			score += 500_000
		default:
			score -= 300_000
		}
		shortEdge := candidate.width
		if candidate.height < shortEdge {
			shortEdge = candidate.height
		}
		if shortEdge > 2000 {
			shortEdge = 2000
		}
		score += float64(shortEdge)
	} else if candidate.sourcePriority >= 300 {
		score += 350_000
	}
	if strings.Contains(candidate.url, "ytimg.com/vi/") || strings.Contains(candidate.url, "ytimg.com/vi_webp/") {
		score -= 800_000
	}
	return score
}

func valueAt(root map[string]interface{}, path ...string) interface{} {
	current := interface{}(root)
	for _, key := range path {
		asMap, ok := current.(map[string]interface{})
		if !ok {
			return nil
		}
		current = asMap[key]
	}
	return current
}
