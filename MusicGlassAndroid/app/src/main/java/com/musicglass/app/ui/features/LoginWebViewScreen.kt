package com.musicglass.app.ui.features

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import com.musicglass.app.youtubemusic.AuthService
import org.json.JSONObject

@SuppressLint("SetJavaScriptEnabled")
@Composable
fun LoginWebViewScreen(
    onLoginSuccess: () -> Unit
) {
    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { context ->
            WebView(context).apply {
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.userAgentString =
                    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Mobile Safari/537.36"

                webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView, url: String?) {
                        super.onPageFinished(view, url)
                        if (url?.contains("music.youtube.com") != true) return

                        val script = """
                            (() => {
                              const cfg = (window.ytcfg && window.ytcfg.data_) || (window.yt && window.yt.config_) || {};
                              const getValue = (key) => {
                                if (window.ytcfg && typeof window.ytcfg.get === 'function') {
                                  const value = window.ytcfg.get(key);
                                  if (value) return value;
                                }
                                return cfg[key] || null;
                              };
                              return JSON.stringify({
                                dataSyncId: getValue('DATASYNC_ID'),
                                visitorData: getValue('VISITOR_DATA')
                              });
                            })();
                        """.trimIndent()

                        evaluateJavascript(script) { result ->
                            val jsonText = result
                                ?.removeSurrounding("\"")
                                ?.replace("\\\"", "\"")
                                ?.replace("\\\\", "\\")
                            val json = runCatching { JSONObject(jsonText ?: "{}") }.getOrNull()
                            val dataSyncId = json?.optString("dataSyncId")?.substringBefore("||")?.takeIf { it.isNotBlank() }
                            val visitorData = json?.optString("visitorData")?.takeIf { it.isNotBlank() }
                            val cookieManager = CookieManager.getInstance()
                            val cookieHeader = listOfNotNull(
                                cookieManager.getCookie("https://music.youtube.com"),
                                cookieManager.getCookie("https://youtube.com"),
                                cookieManager.getCookie("https://google.com")
                            )
                                .flatMap { it.split(";") }
                                .map { it.trim() }
                                .filter { it.isNotBlank() }
                                .distinctBy { it.substringBefore("=") }
                                .joinToString("; ")

                            val hasSapisid = cookieHeader.contains("SAPISID=") || cookieHeader.contains("__Secure-3PAPISID=")
                            if (hasSapisid && dataSyncId != null) {
                                AuthService.save(cookieHeader, dataSyncId, visitorData)
                                onLoginSuccess()
                            }
                        }
                    }
                }

                CookieManager.getInstance().setAcceptCookie(true)
                CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                loadUrl("https://accounts.google.com/ServiceLogin?service=youtube&passive=true&continue=https://music.youtube.com/")
            }
        }
    )
}
