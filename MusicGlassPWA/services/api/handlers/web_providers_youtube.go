package handlers

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

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

// youtubeProviderPayload construit l'état du provider YouTube Music partagé par
// WebLibrary et WebYouTubeProviderStatus. L'appel DELETE de connexion OAuth
// n'est effectué qu'une fois ici (au lieu de trois inline précédemment).
func (h *Handler) youtubeProviderPayload(userID int) gin.H {
	oauthConnected := userID > 0 && h.youtubeOAuthConnected(userID)
	configured := youtubeProviderConfigured()
	status := youtubeProviderStatus()
	if oauthConnected && !configured {
		status = "oauth_connected"
	}
	return gin.H{
		"id":              "youtube_music",
		"name":            "YouTube Music",
		"connected":       oauthConnected || configured,
		"oauth_connected": oauthConnected,
		"oauth_available": googleOAuthConfigured(),
		"playback_ready":  configured,
		"status":          status,
		"server_only":     true,
	}
}

func (h *Handler) WebYouTubeProviderStatus(c *gin.Context) {
	c.JSON(http.StatusOK, h.youtubeProviderPayload(c.GetInt("user_id")))
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
