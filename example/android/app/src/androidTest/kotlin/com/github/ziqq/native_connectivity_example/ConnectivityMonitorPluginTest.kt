package com.github.ziqq.native_connectivity_example

import android.content.Context
import android.content.ContextWrapper
import androidx.test.platform.app.InstrumentationRegistry
import com.github.ziqq.connectivity.ConnectivityMonitorPlugin
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit.MILLISECONDS
import java.util.concurrent.TimeUnit.SECONDS
import java.util.concurrent.atomic.AtomicInteger
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ConnectivityMonitorPluginTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val plugin = ConnectivityMonitorPlugin()
    private lateinit var engine: FlutterEngine

    private val failingLookups = AtomicInteger()
    private val lookups = AtomicInteger()
    private val errors = LinkedBlockingQueue<String>()
    private val available = CountDownLatch(1)

    @Before
    fun setUp() {
        val context = object : ContextWrapper(instrumentation.targetContext) {
            override fun getApplicationContext(): Context = this

            override fun getSystemService(name: String): Any? {
                if (name == CONNECTIVITY_SERVICE) {
                    // Fail individual registration attempts before they reach Binder.
                    if (lookups.incrementAndGet() <= failingLookups.get()) {
                        throw IllegalStateException("Connectivity service temporarily unavailable in test")
                    }
                }
                return super.getSystemService(name)
            }
        }

        instrumentation.runOnMainSync {
            engine = FlutterEngine(context, null, false)
            engine.plugins.add(plugin)
        }
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { engine.destroy() }
    }

    @Test
    fun receivesAvailablePathWithHealthyRegistration() {
        listen()

        assertTrue("Expected a default network on the test device", available.await(5, SECONDS))
        assertTrue("Expected no registration error", errors.isEmpty())
    }

    @Test
    fun recoversTheSameSubscriptionAfterOneRegistrationFailure() {
        listen(failures = 1)

        assertEquals("network_callback_failed", errors.poll(5, SECONDS))
        val recovered = available.await(5, SECONDS)
        assertTrue(
            "Expected a native available path after the retry (service lookups: ${lookups.get()})",
            recovered,
        )
        assertEquals(2, lookups.get())
    }

    @Test
    fun stopsRetryingAfterTheSecondRegistrationFailure() {
        listen(failures = 3)

        repeat(2) { assertEquals("network_callback_failed", errors.poll(5, SECONDS)) }
        assertNull("Expected no third registration attempt", errors.poll(1_500, MILLISECONDS))
        assertEquals(2, lookups.get())
    }

    @Test
    fun cancelsThePendingRetryWithTheSubscription() {
        listen(failures = 1, onError = { plugin.onCancel(null) })

        assertEquals("network_callback_failed", errors.poll(5, SECONDS))
        assertFalse("Expected no path after cancellation", available.await(1_500, MILLISECONDS))
        assertEquals(1, lookups.get())
    }

    private fun listen(failures: Int = 0, onError: () -> Unit = {}) {
        instrumentation.runOnMainSync {
            lookups.set(0)
            failingLookups.set(failures)
            plugin.onListen(null, object : EventChannel.EventSink {
                override fun success(event: Any?) {
                    if (event == "satisfied") available.countDown()
                }

                override fun error(code: String, message: String?, details: Any?) {
                    onError()
                    errors.add(code)
                }

                override fun endOfStream() = Unit
            })
        }
    }
}
