package com.musicglass.app.playback

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.receiveAsFlow

class NetworkConnectivityObserver(context: Context) {
    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private val _networkStatus = Channel<Boolean>(Channel.CONFLATED)
    val networkStatus = _networkStatus.receiveAsFlow()

    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            _networkStatus.trySend(isCurrentlyConnected())
        }

        override fun onLost(network: Network) {
            _networkStatus.trySend(isCurrentlyConnected())
        }

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
            _networkStatus.trySend(isCurrentlyConnected())
        }
    }

    init {
        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .build()

        runCatching {
            connectivityManager.registerNetworkCallback(request, networkCallback)
        }.onFailure {
            _networkStatus.trySend(true)
        }
        _networkStatus.trySend(isCurrentlyConnected())
    }

    fun isCurrentlyConnected(): Boolean {
        return runCatching {
            val activeNetwork = connectivityManager.activeNetwork ?: return false
            val capabilities = connectivityManager.getNetworkCapabilities(activeNetwork) ?: return false
            val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            val isValidated = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
            hasInternet && isValidated
        }.getOrDefault(false)
    }

    fun unregister() {
        runCatching {
            connectivityManager.unregisterNetworkCallback(networkCallback)
        }
    }
}
