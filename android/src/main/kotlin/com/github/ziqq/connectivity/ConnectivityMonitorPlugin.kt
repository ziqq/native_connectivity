package com.github.ziqq.connectivity

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class ConnectivityMonitorPlugin : FlutterPlugin, EventChannel.StreamHandler {
	private val main = Handler(Looper.getMainLooper())
	private var observation: Observation? = null

	private lateinit var executor: ExecutorService
	private lateinit var channel: EventChannel
	private lateinit var context: Context

	override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		context = binding.applicationContext
		executor = Executors.newSingleThreadExecutor()
		channel = EventChannel(binding.binaryMessenger, "github.com/ziqq/connectivity_monitor")
		channel.setStreamHandler(this)
	}

	override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
		channel.setStreamHandler(null)
		onCancel(null)
		executor.shutdown()
	}

	override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
		onCancel(null)
		val next = Observation(context, events)
		observation = next
		// Register and unregister in order while keeping Binder calls off the main thread.
		executor.execute { next.register(retryOnFailure = true) }
	}

	override fun onCancel(arguments: Any?) {
		val previous = observation ?: return
		observation = null
		previous.cancel()
	}

	private inner class Observation(
		private val applicationContext: Context,
		private val events: EventChannel.EventSink,
	) : ConnectivityManager.NetworkCallback() {
		private var manager: ConnectivityManager? = null // Registration executor.
		private var currentNetwork: Network? = null // Main thread.
		private val retry = Runnable { executor.execute { register(retryOnFailure = false) } }

		fun register(retryOnFailure: Boolean) {
			try {
				val connectivity = checkNotNull(applicationContext.getSystemService(ConnectivityManager::class.java)) {
					"Connectivity service unavailable"
				}
				connectivity.registerDefaultNetworkCallback(this)
				manager = connectivity
			} catch (error: RuntimeException) {
				Log.w("ConnectivityMonitor", "Network callback registration failed", error)
				main.post {
					if (observation !== this) return@post
					// Give the service time to recover before retrying this subscription once.
					if (retryOnFailure) main.postDelayed(retry, 1_000L)
					events.error("network_callback_failed", error.message, null)
				}
			}
		}

		fun cancel() {
			main.removeCallbacks(retry)
			executor.execute { unregister() }
		}

		private fun unregister() {
			try {
				manager?.unregisterNetworkCallback(this)
			} catch (error: RuntimeException) {
				Log.w("ConnectivityMonitor", "Network callback removal failed", error)
			}
		}

		override fun onAvailable(network: Network) {
			main.post {
				if (observation !== this || currentNetwork == network) return@post
				currentNetwork = network
				events.success("satisfied")
			}
		}

		override fun onLost(network: Network) {
			main.post {
				if (observation !== this || currentNetwork != network) return@post
				currentNetwork = null
				events.success("unsatisfied")
			}
		}
	}
}
