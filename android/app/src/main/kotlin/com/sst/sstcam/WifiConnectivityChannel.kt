package com.sst.sstcam

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel

/**
 * D1a (U5): observes the PHONE's own Wi-Fi (STA) transport via a
 * [ConnectivityManager.NetworkCallback] and streams a boolean to Dart — `true`
 * when the phone has a Wi-Fi network, `false` once the last one is lost.
 *
 * The app uses this to auto-revert the camera from shared-WiFi (S2) back to the
 * direct WiFi-Direct (P2P) link when the phone drops the shared network, so live
 * preview keeps working — WITHOUT any reconnect loop (the lean-recovery model).
 * This channel only OBSERVES; it never mutates network state.
 */
class WifiConnectivityChannel(private val context: Context) : EventChannel.StreamHandler {
    companion object {
        private const val TAG = "WifiConnectivityChannel"
        private const val EVENT_CHANNEL = "com.sst.sstcam/wifi_connectivity"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private val main = Handler(Looper.getMainLooper())

    private val connectivityManager: ConnectivityManager?
        get() = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    fun register(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        val manager = connectivityManager
        if (manager == null) {
            // Fail OPEN: without a ConnectivityManager we cannot observe, so report
            // "wifi present" and never spuriously strand the camera off S2.
            emit(true)
            return
        }
        // Seed the observer with the CURRENT aggregate state before any transition.
        emit(hasWifiTransport(manager))
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = emit(true)
            // onLost fires for one network; re-derive the AGGREGATE so another
            // Wi-Fi network still counts as available.
            override fun onLost(network: Network) = emit(hasWifiTransport(manager))
        }
        callback = cb
        try {
            manager.registerNetworkCallback(request, cb)
        } catch (e: Throwable) {
            Log.e(TAG, "registerNetworkCallback failed: $e")
        }
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { cb ->
            try {
                connectivityManager?.unregisterNetworkCallback(cb)
            } catch (_: Throwable) {
                // already unregistered / never registered — nothing to do
            }
        }
        callback = null
        eventSink = null
    }

    /** True when the phone currently has ANY Wi-Fi-transport network. */
    private fun hasWifiTransport(manager: ConnectivityManager): Boolean =
        manager.allNetworks.any { net ->
            manager.getNetworkCapabilities(net)
                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }

    private fun emit(available: Boolean) {
        main.post { eventSink?.success(available) }
    }
}
