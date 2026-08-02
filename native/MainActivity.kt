package com.fgi.focusboat.focus_boat

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "focusboat/network"
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val cm = getSystemService(CONNECTIVITY_SERVICE) as ConnectivityManager
            when (call.method) {
                "forceWifi" -> {
                    val request = NetworkRequest.Builder()
                        .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                        .build()
                    var resultSent = false
                    val callback = object : ConnectivityManager.NetworkCallback() {
                        override fun onAvailable(network: Network) {
                            cm.bindProcessToNetwork(network)
                            if (!resultSent) {
                                resultSent = true
                                result.success(true)
                            }
                        }
                    }
                    networkCallback?.let { try { cm.unregisterNetworkCallback(it) } catch (e: Exception) {} }
                    networkCallback = callback
                    cm.requestNetwork(request, callback)
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (!resultSent) {
                            resultSent = true
                            result.success(false)
                        }
                    }, 3000)
                }
                "releaseWifi" -> {
                    cm.bindProcessToNetwork(null)
                    networkCallback?.let { try { cm.unregisterNetworkCallback(it) } catch (e: Exception) {} }
                    networkCallback = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
