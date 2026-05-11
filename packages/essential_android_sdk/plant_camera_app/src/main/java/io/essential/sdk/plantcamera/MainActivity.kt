package io.essential.sdk.plantcamera

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialServiceConfiguration
import io.essential.sdk.android.EssentialTaskRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID

class MainActivity : ComponentActivity() {
    private val scope = MainScope()
    private var imageCapture: ImageCapture? = null
    private lateinit var previewView: PreviewView
    private lateinit var resultTitle: TextView
    private lateinit var resultBody: TextView
    private lateinit var statusText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = Color.BLACK
        setContentView(buildContent())
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), REQUEST_CAMERA)
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CAMERA && grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else {
            statusText.text = "Camera permission is required"
        }
    }

    private fun buildContent(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(BACKGROUND)
        }
        previewView = PreviewView(this).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        root.addView(previewView, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(controlPanel())
        return root
    }

    private fun controlPanel(): View {
        statusText = text("Move close enough to show leaves, flowers, or fruit", 13f, MUTED, false)
        resultTitle = text("Plant name", 24f, TEXT, true)
        resultBody = text("Tap capture to see candidate names and evidence.", 15f, MUTED, false)
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(16), dp(18), dp(18))
            background = rounded(Color.WHITE, Color.TRANSPARENT, dp(26).toFloat())
            addView(statusText)
            addView(resultTitle)
            addView(resultBody)
            addView(
                Button(this@MainActivity).apply {
                    text = "Capture"
                    textSize = 20f
                    isAllCaps = false
                    setTextColor(Color.WHITE)
                    background = rounded(ACCENT, ACCENT, dp(28).toFloat())
                    setOnClickListener { captureAndIdentify() }
                },
                LinearLayout.LayoutParams(-1, dp(62)).apply {
                    setMargins(0, dp(14), 0, 0)
                },
            )
        }
    }

    private fun startCamera() {
        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener({
            val provider = providerFuture.get()
            val preview = Preview.Builder().build().also {
                it.setSurfaceProvider(previewView.surfaceProvider)
            }
            imageCapture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .build()
            provider.unbindAll()
            provider.bindToLifecycle(
                this,
                CameraSelector.DEFAULT_BACK_CAMERA,
                preview,
                imageCapture,
            )
            statusText.text = "Camera ready"
        }, ContextCompat.getMainExecutor(this))
    }

    private fun captureAndIdentify() {
        val capture = imageCapture ?: return
        val file = File(cacheDir, "plant-${System.currentTimeMillis()}.jpg")
        val options = ImageCapture.OutputFileOptions.Builder(file).build()
        statusText.text = "Capturing..."
        capture.takePicture(
            options,
            ContextCompat.getMainExecutor(this),
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(outputFileResults: ImageCapture.OutputFileResults) {
                    identify(file)
                }

                override fun onError(exception: ImageCaptureException) {
                    statusText.text = "Capture failed"
                    resultBody.text = exception.message ?: "Camera error"
                }
            },
        )
    }

    private fun identify(file: File) {
        statusText.text = "Checking plant candidates..."
        resultTitle.text = "Analyzing"
        resultBody.text = "Using the plant engine first, then Essential for an on-device explanation if needed."
        scope.launch {
            val plantNet = runCatching {
                withContext(Dispatchers.IO) {
                    PlantNetClient(BuildConfig.PLANTNET_API_KEY).identify(file)
                }
            }.getOrNull()
            if (plantNet != null) {
                resultTitle.text = plantNet.name
                resultBody.text = plantNet.description
                statusText.text = "Identified with Pl@ntNet"
                return@launch
            }

            runCatching {
                val client = EssentialClient.connect(
                    this@MainActivity,
                    EssentialServiceConfiguration(
                        servicePackage = "com.example.essential_flutter",
                        serviceClassName = "com.example.essential_flutter.service.EssentialService",
                        defaultModelId = PREFERRED_MODEL_ID,
                    ),
                )
                try {
                    val request = EssentialTaskRequest.plantIdentification(
                        prompt = "Describe this plant in English. Include candidate species, confidence caveats, visible evidence, and any extra leaf, flower, fruit, or whole-plant details needed.",
                        image = EssentialMediaAttachment(
                            kind = EssentialMediaKind.IMAGE,
                            uri = Uri.fromFile(file).toString(),
                            mimeType = "image/jpeg",
                        ),
                        modelRequirement = EssentialModelRequirement.fallback(
                            preferredModelId = PREFERRED_MODEL_ID,
                            capability = "plant_identification",
                            minContextWindow = 2048,
                        ),
                    ).copy(maxTokens = 96, timeoutMs = 60_000)
                    client.runTask(request)
                } finally {
                    client.close()
                }
            }.onSuccess { result ->
                resultTitle.text = "Candidate explanation"
                resultBody.text = result.text.ifBlank { "No result was returned." }
                statusText.text = "Explained by Essential"
            }.onFailure { error ->
                resultTitle.text = "Could not identify"
                resultBody.text = if (BuildConfig.PLANTNET_API_KEY.isBlank()) {
                    "Set a Pl@ntNet API key for species-level identification. The built-in SSD MobileNet fallback is a general COCO object detector, not a plant species classifier."
                } else {
                    error.message ?: error.javaClass.simpleName
                }
                statusText.text = "Setup required"
            }
        }
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean): TextView {
        return TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            if (bold) typeface = Typeface.DEFAULT_BOLD
            gravity = Gravity.START
            setLineSpacing(2f, 1.08f)
        }
    }

    private fun rounded(fill: Int, stroke: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            setColor(fill)
            cornerRadius = radius
            if (stroke != Color.TRANSPARENT) {
                setStroke(dp(1), stroke)
            }
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private data class PlantResult(val name: String, val description: String)

    private class PlantNetClient(private val apiKey: String) {
        fun identify(file: File): PlantResult? {
            if (apiKey.isBlank()) {
                return null
            }
            val boundary = "essential-${UUID.randomUUID()}"
            val connection = (URL("https://my-api.plantnet.org/v2/identify/all?api-key=$apiKey&lang=ja&nb-results=3")
                .openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                connectTimeout = 20_000
                readTimeout = 45_000
                setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
            }
            connection.outputStream.use { output ->
                output.write("--$boundary\r\n".toByteArray())
                output.write("Content-Disposition: form-data; name=\"images\"; filename=\"plant.jpg\"\r\n".toByteArray())
                output.write("Content-Type: image/jpeg\r\n\r\n".toByteArray())
                file.inputStream().use { it.copyTo(output) }
                output.write("\r\n--$boundary\r\n".toByteArray())
                output.write("Content-Disposition: form-data; name=\"organs\"\r\n\r\n".toByteArray())
                output.write("auto\r\n".toByteArray())
                output.write("--$boundary--\r\n".toByteArray())
            }
            val body = if (connection.responseCode in 200..299) {
                connection.inputStream.bufferedReader().readText()
            } else {
                connection.errorStream?.bufferedReader()?.readText().orEmpty()
            }
            if (connection.responseCode !in 200..299) {
                error(body.ifBlank { "PlantNet HTTP ${connection.responseCode}" })
            }
            val json = JSONObject(body)
            val results = json.optJSONArray("results")
            val first = results?.optJSONObject(0) ?: return null
            val species = first.optJSONObject("species")
            val scientific = species?.optString("scientificNameWithoutAuthor").orEmpty()
            val common = species
                ?.optJSONArray("commonNames")
                ?.optString(0)
                .orEmpty()
            val score = first.optDouble("score", 0.0)
            val name = common.ifBlank { scientific.ifBlank { json.optString("bestMatch", "Plant candidate") } }
            return PlantResult(
                name = name,
                description = "Scientific name: ${scientific.ifBlank { "Unknown" }}\nConfidence: ${(score * 100).toInt()}%\nThe result depends on photo quality. Add the front and back of leaves, flowers, fruit, and the whole plant for better accuracy.",
            )
        }
    }

    private companion object {
        const val REQUEST_CAMERA = 20
        const val PREFERRED_MODEL_ID = "gemma-4-e4b-it"
        const val BACKGROUND = 0xFF0B1511.toInt()
        const val TEXT = 0xFF14211B.toInt()
        const val MUTED = 0xFF607268.toInt()
        const val ACCENT = 0xFF177C5D.toInt()
    }
}
