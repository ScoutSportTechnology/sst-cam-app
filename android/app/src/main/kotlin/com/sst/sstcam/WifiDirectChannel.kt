package com.sst.sstcam

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.*
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class WifiDirectChannel(private val context: Context) : MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val TAG = "WifiDirectChannel"
        private const val METHOD_CHANNEL = "com.sst.sstcam/wifi"
        private const val EVENT_CHANNEL = "com.sst.sstcam/wifi/state"

        // State codes matching WifiDirectState enum in Dart
        private const val STATE_IDLE = 0
        private const val STATE_STARTING = 1
        private const val STATE_CONNECTED = 2
        private const val STATE_FAILED = 3
        private const val STATE_STOPPING = 4
    }

    private var wifiP2pManager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var broadcastReceiver: BroadcastReceiver? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(this)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(this)
    }

    fun initialize(activity: android.app.Activity) {
        try {
            wifiP2pManager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
            channel = wifiP2pManager?.initialize(context, activity.mainLooper, null)
            Log.d(TAG, "WifiP2pManager initialized")
        } catch (e: Throwable) {
            Log.e(TAG, "WifiP2pManager.initialize failed: $e")
            wifiP2pManager = null
            channel = null
            // Post failed state to any open sink
            eventSink?.success(STATE_FAILED)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "connect" -> {
                val ssid = call.argument<String>("ssid")
                    ?: return result.error("INVALID", "ssid required", null)
                val psk = call.argument<String>("psk")
                    ?: return result.error("INVALID", "psk required", null)
                connect(ssid, psk, result)
            }
            "disconnect" -> disconnect(result)
            else -> result.notImplemented()
        }
    }

    private fun connect(ssid: String, psk: String, result: Result) {
        // SSID/PSK-based join via WifiP2pConfig.Builder requires API 29 (Android 10+).
        // The pre-Q WifiP2pConfig API requires a peer MAC address from prior discovery,
        // which we do not perform — attempting it with an empty address always fails.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            eventSink?.success(STATE_FAILED)
            result.error("UNSUPPORTED", "WiFi Direct credential-based join requires Android 10+", null)
            return
        }

        val mgr = wifiP2pManager
            ?: return result.error("UNAVAILABLE", "WifiP2pManager not initialized", null)
        val ch = channel
            ?: return result.error("UNAVAILABLE", "WifiP2pManager channel not available", null)

        val config = WifiP2pConfig.Builder()
            .setNetworkName(ssid)
            .setPassphrase(psk)
            .build()

        // Clear any lingering P2P group from a previous session BEFORE joining.
        // Calling connect() while a stale group is still up (the app was closed
        // or backgrounded without a clean disconnect, so p2p-wlan0-0 persists)
        // intermittently fails with BUSY (reason 2) — the "wifi failed" seen after
        // a few app close/reopen cycles. removeGroup is best-effort: a clean
        // remove and a "no group present" failure both proceed to the join. The
        // receiver is registered only AFTER removal (in doConnect) so the remove's
        // own connection-changed broadcast isn't forwarded as a spurious
        // disconnect mid-connect.
        mgr.removeGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                doConnect(mgr, ch, config, result)
            }
            override fun onFailure(reason: Int) {
                doConnect(mgr, ch, config, result)
            }
        })
    }

    private fun doConnect(
        mgr: WifiP2pManager,
        ch: WifiP2pManager.Channel,
        config: WifiP2pConfig,
        result: Result,
    ) {
        // Register broadcast receiver to get connection state
        registerReceiver()

        mgr.connect(ch, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                result.success(null)
            }
            override fun onFailure(reason: Int) {
                unregisterReceiver()
                eventSink?.success(STATE_FAILED)
                result.error("CONNECT_FAILED", "WifiP2p connect failed: $reason", null)
            }
        })
    }

    private fun disconnect(result: Result) {
        val mgr = wifiP2pManager ?: return result.success(null)
        val ch = channel ?: return result.success(null)

        eventSink?.success(STATE_STOPPING)
        mgr.removeGroup(ch, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                eventSink?.success(STATE_IDLE)
                unregisterReceiver()
                result.success(null)
            }
            override fun onFailure(reason: Int) {
                eventSink?.success(STATE_IDLE)
                unregisterReceiver()
                result.success(null)
            }
        })
    }

    private fun registerReceiver() {
        unregisterReceiver()
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
        }
        broadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                when (intent.action) {
                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                WifiP2pManager.EXTRA_WIFI_P2P_INFO,
                                WifiP2pInfo::class.java
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
                        }
                        if (info?.isGroupOwner == false && info.groupFormed) {
                            eventSink?.success(STATE_CONNECTED)
                        } else if (info?.isGroupOwner == true && info.groupFormed) {
                            // Device became group owner unexpectedly; we only join as client.
                            Log.w(TAG, "Device became GO unexpectedly; emitting STATE_FAILED")
                            eventSink?.success(STATE_FAILED)
                        } else if (info?.groupFormed == false) {
                            eventSink?.success(STATE_IDLE)
                        }
                    }
                }
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(broadcastReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(broadcastReceiver, filter)
        }
    }

    private fun unregisterReceiver() {
        broadcastReceiver?.let {
            try { context.unregisterReceiver(it) } catch (_: Exception) {}
            broadcastReceiver = null
        }
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        unregisterReceiver()
        eventSink = null
    }
}
