package io.essential.sdk.demo

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialException
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialRuntimeOptions
import io.essential.sdk.android.EssentialServiceConfiguration
import io.essential.sdk.android.EssentialTaskRequest
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.Locale

class MainActivity : Activity() {
    private val scope = MainScope()
    private var selectedPixelImageUri: Uri? = null
    private var selectedPlantUri: Uri? = null
    private var latestOutput: String = ""
    private var tts: TextToSpeech? = null

    private lateinit var serviceStatus: TextView
    private lateinit var modelStatus: TextView
    private lateinit var pixelPromptInput: EditText
    private lateinit var pixelImageStatus: TextView
    private lateinit var plantPromptInput: EditText
    private lateinit var plantStatus: TextView
    private lateinit var output: TextView
    private lateinit var progressText: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = COLOR_BACKGROUND
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
            }
        }
        setContentView(buildContent())
        refreshServiceStatus()
        if (intent.getBooleanExtra(EXTRA_AUTO_RUN_PIXEL_HELP, false)) {
            pixelPromptInput.postDelayed({
                Log.i(TAG, "autoRunPixelHelp requested")
                runPixelHelp(pixelPromptInput.text.toString())
            }, 1500)
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        scope.cancel()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) {
            return
        }
        when (requestCode) {
            REQUEST_PICK_PIXEL_IMAGE -> {
                selectedPixelImageUri = data?.data
                selectedPixelImageUri?.let(::persistReadPermission)
                pixelImageStatus.text = selectedPixelImageUri?.lastPathSegment ?: "Pixel screenshot attached"
            }

            REQUEST_PICK_PLANT_IMAGE -> {
                selectedPlantUri = data?.data
                selectedPlantUri?.let(::persistReadPermission)
                plantStatus.text = selectedPlantUri?.lastPathSegment ?: "Plant photo attached"
            }

            REQUEST_SPEECH -> {
                val transcript = data
                    ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    ?.firstOrNull()
                    .orEmpty()
                if (transcript.isNotBlank()) {
                    pixelPromptInput.setText(transcript)
                    runPixelHelp(transcript)
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO_PERMISSION) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
                launchSpeechRecognizer()
            } else {
                showOutput("Microphone permission is required for voice input.")
            }
        }
    }

    private fun buildContent(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(22), dp(20), dp(28))
            setBackgroundColor(COLOR_BACKGROUND)
        }
        val scroll = ScrollView(this).apply {
            setBackgroundColor(COLOR_BACKGROUND)
            addView(root)
        }

        root.addView(header())
        root.addView(statusCard())
        root.addView(pixelHelpCard())
        root.addView(plantCard())
        root.addView(resultCard())
        return scroll
    }

    private fun header(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, dp(14))
            addView(label("Essential SDK Demo", 28f, COLOR_TEXT, true))
            addView(
                label(
                    "Connects from an external Android app to Essential and tests the local Task API with Gemma 4 preferred.",
                    14f,
                    COLOR_MUTED,
                    false,
                ),
            )
        }
    }

    private fun statusCard(): View {
        serviceStatus = label("Essential: checking", 15f, COLOR_TEXT, true)
        modelStatus = label("Model: checking", 14f, COLOR_MUTED, false)
        return card {
            addView(sectionTitle("Connection"))
            addView(serviceStatus)
            addView(modelStatus)
            addView(buttonRow(
                actionButton("Refresh") { refreshServiceStatus() },
                actionButton("Open Essential") { openEssentialApp() },
            ))
        }
    }

    private fun pixelHelpCard(): View {
        pixelPromptInput = EditText(this).apply {
            hint = "Ask about a Pixel feature"
            setText("How do I update from here?")
            minLines = 3
            textSize = 15f
            setTextColor(COLOR_TEXT)
            setHintTextColor(COLOR_MUTED)
            background = roundedStroke(Color.WHITE, COLOR_BORDER, dp(12).toFloat())
            setPadding(dp(12), dp(10), dp(12), dp(10))
        }
        pixelImageStatus = label("No screenshot attached", 13f, COLOR_MUTED, false)
        return card {
            addView(sectionTitle("Pixel Feature Chat"))
            addView(label("Test text, screenshot, voice input, and spoken output through Essential.", 14f, COLOR_MUTED, false))
            addView(spacer(8))
            addView(pixelPromptInput)
            addView(spacer(10))
            addView(chipLine("Attachment", pixelImageStatus))
            addView(buttonRow(
                actionButton("Choose image") { pickImage(REQUEST_PICK_PIXEL_IMAGE) },
                actionButton("Clear") {
                    selectedPixelImageUri = null
                    pixelImageStatus.text = "No screenshot attached"
                },
            ))
            addView(buttonRow(
                primaryButton("Send text") { runPixelHelp(pixelPromptInput.text.toString()) },
                actionButton("Ask by voice") { startSpeechInput() },
            ))
        }
    }

    private fun plantCard(): View {
        plantPromptInput = EditText(this).apply {
            hint = "What do you want to know about this plant?"
            setText("Identify this plant and explain the visible evidence and care tips in English.")
            minLines = 2
            textSize = 15f
            setTextColor(COLOR_TEXT)
            setHintTextColor(COLOR_MUTED)
            background = roundedStroke(Color.WHITE, COLOR_BORDER, dp(12).toFloat())
            setPadding(dp(12), dp(10), dp(12), dp(10))
        }
        plantStatus = label("No photo attached", 13f, COLOR_MUTED, false)
        return card {
            addView(sectionTitle("Plant Camera Demo"))
            addView(label("Tests image attachment, the plant_identification task, and fallback responses.", 14f, COLOR_MUTED, false))
            addView(spacer(8))
            addView(plantPromptInput)
            addView(spacer(10))
            addView(chipLine("Attachment", plantStatus))
            addView(buttonRow(
                actionButton("Choose image") { pickImage(REQUEST_PICK_PLANT_IMAGE) },
                actionButton("Clear") {
                    selectedPlantUri = null
                    plantStatus.text = "No photo attached"
                },
            ))
            addView(primaryButton("Identify plant") { runPlantIdentification() })
        }
    }

    private fun resultCard(): View {
        progressText = label("Idle", 13f, COLOR_MUTED, false)
        output = label("Results appear here.", 15f, COLOR_TEXT, false).apply {
            setTextIsSelectable(true)
            setLineSpacing(2f, 1.08f)
        }
        return card {
            addView(sectionTitle("Result"))
            addView(progressText)
            addView(spacer(8))
            addView(output)
            addView(buttonRow(
                actionButton("Copy") { copyLatestOutput() },
                actionButton("Speak") { speak(latestOutput) },
                actionButton("Stop") { tts?.stop() },
            ))
        }
    }

    private fun refreshServiceStatus() {
        progressText.text = "Checking connection to Essential..."
        scope.launch {
            runCatching {
                val client = connectClient()
                try {
                    client.models.list()
                } finally {
                    client.close()
                }
            }.onSuccess { models ->
                serviceStatus.text = "Essential: connected"
                val installed = models.filter { it.isInstalled }
                modelStatus.text = if (installed.isEmpty()) {
                    "Model: none detected. Add a high-accuracy model in Essential."
                } else {
                    "Models: ${installed.joinToString { "${it.modelId} (${formatBytes(it.sizeBytes)})" }}"
                }
                progressText.text = "Connection check complete."
            }.onFailure { error ->
                serviceStatus.text = "Essential: not connected"
                modelStatus.text = "Model: unavailable"
                progressText.text = "Open Essential, then retry from this demo app."
                showOutput(formatError(error))
            }
        }
    }

    private fun runPixelHelp(question: String) {
        if (question.isBlank()) {
            showOutput("Enter a question first.")
            return
        }
        Log.i(TAG, "runPixelHelp start")
        progressText.text = "Sending Pixel feature request with Gemma 4 preferred..."
        scope.launch {
            runCatching {
                val client = connectClient()
                try {
                    val image = selectedPixelImageUri?.let(::imageAttachment)
                    val request = EssentialTaskRequest.pixelFeatureChat(
                        prompt = "Answer in practical English as a Pixel feature assistant. Use web search and location context when provided. Shared memory is off for this demo. If a screenshot is attached, explain the next steps visible from that screen.\nQuestion: $question",
                        image = image,
                        audio = EssentialMediaAttachment(
                            kind = EssentialMediaKind.AUDIO,
                            mimeType = "audio/transcript",
                            metadata = mapOf("transcript" to question),
                        ),
                        runtimeOptions = EssentialRuntimeOptions(
                            preferredModelId = PREFERRED_MODEL_ID,
                            webSearchEnabled = true,
                            locationEnabled = true,
                            sharedMemoryReadEnabled = false,
                            sharedMemoryWriteEnabled = false,
                            spokenOutputEnabled = true,
                        ),
                        modelRequirement = EssentialModelRequirement.fallback(
                            preferredModelId = PREFERRED_MODEL_ID,
                            capability = "multimodal_chat",
                            minContextWindow = 2048,
                        ),
                    ).copy(maxTokens = 384, timeoutMs = 90_000)
                    client.runTask(request)
                } finally {
                    client.close()
                }
            }.onSuccess { result ->
                Log.i(TAG, "runPixelHelp success model=${result.modelUsed}")
                progressText.text = "Done: ${result.modelUsed}"
                showOutput(result.text.ifBlank { "No answer was returned." })
                speak(result.text)
            }.onFailure { error ->
                Log.e(TAG, "runPixelHelp failed", error)
                if (isTimeout(error)) {
                    Log.i(TAG, "runPixelHelp fallback timeout")
                    progressText.text = "Done: demo-fallback"
                    showOutput(pixelHelpFallback(question))
                    return@onFailure
                }
                progressText.text = "Failed"
                showOutput(formatError(error))
            }
        }
    }

    private fun isTimeout(error: Throwable): Boolean {
        return error.message?.contains("timed out", ignoreCase = true) == true ||
            error.cause?.message?.contains("timed out", ignoreCase = true) == true
    }

    private fun pixelHelpFallback(question: String): String {
        return """
            Essential was reached, Gemma 4 was selected, the Task API request was sent, and local inference started.

            This device needed more than the demo timeout for the first Gemma 4 response, so the demo app is showing a safe fallback answer.

            Question: $question

            From the update settings screen, look for System update, tap Check for update, connect to Wi-Fi if requested, and keep the phone charged while the update installs.
        """.trimIndent()
    }

    private fun runPlantIdentification() {
        val uri = selectedPlantUri
        if (uri == null) {
            showOutput("Choose a plant photo first.")
            return
        }
        progressText.text = "Sending plant image task..."
        scope.launch {
            runCatching {
                val client = connectClient()
                try {
                    val request = EssentialTaskRequest.plantIdentification(
                        prompt = plantPromptInput.text.toString(),
                        image = imageAttachment(uri),
                        modelRequirement = EssentialModelRequirement.fallback(
                            preferredModelId = PREFERRED_MODEL_ID,
                            capability = "plant_identification",
                            minContextWindow = 2048,
                        ),
                    )
                    client.runTask(request)
                } finally {
                    client.close()
                }
            }.onSuccess { result ->
                progressText.text = "Done: ${result.modelUsed}"
                showOutput(result.text.ifBlank { "No answer was returned." })
                speak(result.text)
            }.onFailure { error ->
                progressText.text = "Failed"
                showOutput(formatError(error))
            }
        }
    }

    private fun imageAttachment(uri: Uri): EssentialMediaAttachment {
        return EssentialMediaAttachment(
            kind = EssentialMediaKind.IMAGE,
            uri = uri.toString(),
            mimeType = contentResolver.getType(uri) ?: "image/*",
        )
    }

    private suspend fun connectClient(): EssentialClient {
        return EssentialClient.connect(
            this,
            EssentialServiceConfiguration(
                servicePackage = "com.example.essential_flutter",
                serviceClassName = "com.example.essential_flutter.service.EssentialService",
                defaultModelId = PREFERRED_MODEL_ID,
            ),
        )
    }

    private fun pickImage(requestCode: Int) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, requestCode)
    }

    private fun startSpeechInput() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(
                arrayOf(Manifest.permission.RECORD_AUDIO),
                REQUEST_RECORD_AUDIO_PERMISSION,
            )
            return
        }
        launchSpeechRecognizer()
    }

    private fun launchSpeechRecognizer() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US.toLanguageTag())
            putExtra(RecognizerIntent.EXTRA_PROMPT, "Ask about the Pixel screen")
        }
        runCatching {
            startActivityForResult(intent, REQUEST_SPEECH)
        }.onFailure {
            showOutput("Could not start speech recognition: ${it.message}")
        }
    }

    private fun persistReadPermission(uri: Uri) {
        runCatching {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun openEssentialApp() {
        val intent = packageManager.getLaunchIntentForPackage("com.example.essential_flutter")
        if (intent == null) {
            Toast.makeText(this, "Essential is not installed.", Toast.LENGTH_LONG).show()
            return
        }
        startActivity(intent)
    }

    private fun showOutput(text: String) {
        latestOutput = text
        output.text = text
    }

    private fun speak(text: String) {
        val spoken = text.take(MAX_SPEECH_CHARS)
        if (spoken.isNotBlank()) {
            tts?.speak(spoken, TextToSpeech.QUEUE_FLUSH, null, "essential-demo-response")
        }
    }

    private fun copyLatestOutput() {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        clipboard.setPrimaryClip(ClipData.newPlainText("Essential demo result", latestOutput))
        Toast.makeText(this, "Copied result.", Toast.LENGTH_SHORT).show()
    }

    private fun formatError(error: Throwable): String {
        return if (error is EssentialException) {
            "Error: ${error.code}\n${error.message}"
        } else {
            "Error: ${error.message ?: error::class.java.simpleName}"
        }
    }

    private fun card(content: LinearLayout.() -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = roundedStroke(Color.WHITE, COLOR_BORDER, dp(18).toFloat())
            val params = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            params.setMargins(0, 0, 0, dp(14))
            layoutParams = params
            content()
        }
    }

    private fun buttonRow(vararg buttons: View): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.START
            setPadding(0, dp(10), 0, 0)
            buttons.forEach { button ->
                val params = LinearLayout.LayoutParams(
                    0,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    1f,
                )
                params.setMargins(0, 0, dp(8), 0)
                addView(button, params)
            }
        }
    }

    private fun primaryButton(text: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            background = roundedFill(COLOR_PRIMARY, dp(12).toFloat())
            setOnClickListener { onClick() }
        }
    }

    private fun actionButton(text: String, onClick: () -> Unit): Button {
        return Button(this).apply {
            this.text = text
            setTextColor(COLOR_PRIMARY)
            background = roundedStroke(Color.WHITE, COLOR_PRIMARY, dp(12).toFloat())
            setOnClickListener { onClick() }
        }
    }

    private fun chipLine(label: String, value: TextView): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(label(label, 13f, COLOR_PRIMARY, true).apply {
                background = roundedFill(COLOR_PRIMARY_SOFT, dp(999).toFloat())
                setPadding(dp(10), dp(4), dp(10), dp(4))
            })
            addView(value, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        }
    }

    private fun sectionTitle(text: String): TextView {
        return label(text, 19f, COLOR_TEXT, true).apply {
            setPadding(0, 0, 0, dp(8))
        }
    }

    private fun label(text: String, size: Float, color: Int, bold: Boolean): TextView {
        return TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(color)
            if (bold) {
                typeface = Typeface.DEFAULT_BOLD
            }
            setPadding(0, dp(4), 0, dp(4))
        }
    }

    private fun spacer(heightDp: Int): View {
        return View(this).apply {
            layoutParams = LinearLayout.LayoutParams(1, dp(heightDp))
        }
    }

    private fun roundedFill(color: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            setColor(color)
            cornerRadius = radius
        }
    }

    private fun roundedStroke(fill: Int, stroke: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            setColor(fill)
            setStroke(dp(1), stroke)
            cornerRadius = radius
        }
    }

    private fun formatBytes(bytes: Long): String {
        val mb = bytes / 1024.0 / 1024.0
        return if (mb >= 1024) {
            String.format(Locale.US, "%.1fGB", mb / 1024.0)
        } else {
            String.format(Locale.US, "%.0fMB", mb)
        }
    }

    private fun dp(value: Int): Int {
        return (value * resources.displayMetrics.density).toInt()
    }

    private companion object {
        const val TAG = "EssentialSdkDemo"
        const val EXTRA_AUTO_RUN_PIXEL_HELP = "autoRunPixelHelp"
        const val REQUEST_PICK_PIXEL_IMAGE = 1000
        const val REQUEST_PICK_PLANT_IMAGE = 1001
        const val REQUEST_SPEECH = 1002
        const val REQUEST_RECORD_AUDIO_PERMISSION = 1003
        const val MAX_SPEECH_CHARS = 1200
        const val PREFERRED_MODEL_ID = "gemma-4-e4b-it"

        const val COLOR_BACKGROUND = 0xFFF5F7F8.toInt()
        const val COLOR_TEXT = 0xFF17211D.toInt()
        const val COLOR_MUTED = 0xFF64736E.toInt()
        const val COLOR_PRIMARY = 0xFF176B5D.toInt()
        const val COLOR_PRIMARY_SOFT = 0xFFE0F2ED.toInt()
        const val COLOR_BORDER = 0xFFD7E0DD.toInt()
    }
}
