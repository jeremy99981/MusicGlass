package handlers

import (
	"app/middleware"
	"crypto/rand"
	"encoding/base64"
	"net/http"
	"os"
	"strings"

	"github.com/gin-gonic/gin"
)

const refreshCookie = "mg_refresh"

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
