package com.example.essential_flutter

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.example.essential_flutter.service.IEssentialService
import com.example.essential_flutter.service.IEssentialStreamCallback
import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class EssentialServiceAidlTest {
    @Test
    fun runInferenceAndStreamInferenceOverAidl() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val service = bindService(context)
        val callerPackage = InstrumentationRegistry.getInstrumentation().context.packageName

        val models = JSONObject(service.listModels()).getJSONArray("models")
        assertTrue(models.length() >= 1)

        val blockingRequest = JSONObject()
            .put("requestId", "android-test-run")
            .put("callerPackage", callerPackage)
            .put("prompt", "hello")
            .put(
                "modelRequirement",
                JSONObject().put("modelId", "essential-mini"),
            )
            .put(
                "generationParams",
                JSONObject()
                    .put("maxTokens", 16)
                    .put("temperature", 0.0),
            )

        val blockingResponse = JSONObject(service.runInference(blockingRequest.toString()))
        assertTrue(blockingResponse.getString("status") == "completed")
        assertTrue(blockingResponse.getString("modelUsed") == "essential-mini")
        assertTrue(blockingResponse.getString("output").isNotBlank())

        val doneLatch = CountDownLatch(1)
        val chunks = StringBuilder()
        var completedResponse: JSONObject? = null
        var streamError: String? = null

        val callback = object : IEssentialStreamCallback.Stub() {
            override fun onChunk(requestId: String, chunkJson: String) {
                val chunk = JSONObject(chunkJson)
                chunks.append(chunk.getString("delta"))
            }

            override fun onComplete(requestId: String, responseJson: String) {
                completedResponse = JSONObject(responseJson)
                doneLatch.countDown()
            }

            override fun onError(requestId: String, errorCode: String, message: String) {
                streamError = "$errorCode:$message"
                doneLatch.countDown()
            }
        }

        val streamRequest = JSONObject()
            .put("requestId", "android-test-stream")
            .put("callerPackage", callerPackage)
            .put("stream", true)
            .put(
                "input",
                JSONObject().put("prompt", "stream"),
            )
            .put(
                "modelRequirement",
                JSONObject().put("modelId", "essential-mini"),
            )
            .put(
                "generationParams",
                JSONObject()
                    .put("maxTokens", 16)
                    .put("temperature", 0.0),
            )

        service.streamInference(streamRequest.toString(), callback)

        assertTrue(doneLatch.await(10, TimeUnit.SECONDS))
        assertTrue(streamError == null)
        assertTrue(chunks.isNotEmpty())
        assertTrue(completedResponse?.getString("status") == "completed")

        context.unbindService(boundConnection!!)
        boundConnection = null
    }

    private fun bindService(context: Context): IEssentialService {
        val intent = Intent().setClassName(
            context.packageName,
            "com.example.essential_flutter.service.EssentialService",
        )
        val latch = CountDownLatch(1)
        var service: IEssentialService? = null
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                service = IEssentialService.Stub.asInterface(binder)
                latch.countDown()
            }

            override fun onServiceDisconnected(name: ComponentName) = Unit
        }
        boundConnection = connection
        val bound = context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        assertTrue(bound)
        assertTrue(latch.await(10, TimeUnit.SECONDS))
        return requireNotNull(service)
    }

    companion object {
        private var boundConnection: ServiceConnection? = null
    }
}
