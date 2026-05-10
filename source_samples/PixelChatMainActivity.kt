package io.essential.sdk.pixelchat

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Bundle
import android.speech.RecognizerIntent
import android.speech.tts.TextToSpeech
import android.view.Gravity
import android.view.View
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.essential.sdk.android.EssentialClient
import io.essential.sdk.android.EssentialMediaAttachment
import io.essential.sdk.android.EssentialMediaKind
import io.essential.sdk.android.EssentialModelRequirement
import io.essential.sdk.android.EssentialReferenceDocument
import io.essential.sdk.android.EssentialRuntimeOptions
import io.essential.sdk.android.EssentialServiceConfiguration
import io.essential.sdk.android.EssentialTaskRequest
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.Locale

class MainActivity : Activity() {
    private val scope = MainScope()
    private val messages = mutableListOf<Pair<Boolean, String>>()
    private var tts: TextToSpeech? = null
    private var selectedImageUri: Uri? = null
    private var latestAssistantText: String = ""
    private lateinit var statusText: TextView
    private lateinit var modelText: TextView
    private lateinit var messagesColumn: LinearLayout
    private lateinit var input: EditText
    private lateinit var imageStatus: TextView
    private lateinit var scroll: ScrollView
    private var latestAssistantView: TextView? = null
    private val quickGuideText by lazy { readAssetText(PIXEL_GUIDE_TEXT_ASSET) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.statusBarColor = CANVAS
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts?.language = Locale.US
            }
        }
        setContentView(buildContent())
        addMessage(
            false,
            "Ask about Pixel features, settings, or an attached screenshot. This demo is a separate Android app calling Essential as a local on-device AI API.",
        )
        refreshModels()
        handleAutoRun(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleAutoRun(intent)
    }

    override fun onDestroy() {
        tts?.shutdown()
        scope.cancel()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        when (requestCode) {
            REQUEST_SPEECH -> {
                val text = data
                    ?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    ?.firstOrNull()
                    .orEmpty()
                if (text.isNotBlank()) {
                    input.setText(text)
                    send()
                }
            }
            REQUEST_IMAGE -> {
                selectedImageUri = data?.data
                selectedImageUri?.let(::persistReadPermission)
                imageStatus.text = selectedImageUri?.lastPathSegment ?: "Screenshot attached"
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_RECORD_AUDIO &&
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        ) {
            startVoice()
        }
    }

    private fun buildContent(): View {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(18), dp(18), dp(12))
            setBackgroundColor(CANVAS)
        }
        root.addView(header())
        root.addView(statusPanel())
        scroll = ScrollView(this).apply {
            isFillViewport = true
            messagesColumn = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, dp(12), 0, dp(12))
            }
            addView(messagesColumn)
        }
        root.addView(scroll, LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(composer())
        return root
    }

    private fun header(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(2), 0, dp(10))
            addView(text("Pixel Feature Chat", 25f, INK, true))
            addView(text("A compact demo app using Essential through the local AI API.", 13f, MUTED, false))
        }
    }

    private fun statusPanel(): View {
        statusText = text("Essential: checking", 12f, INK, true)
        modelText = text("Web on / Location on / Shared memory off", 11f, MUTED, false)
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = rounded(SURFACE, STROKE, dp(16).toFloat())
            setPadding(dp(14), dp(12), dp(14), dp(12))
            layoutParams = LinearLayout.LayoutParams(-1, -2).apply {
                setMargins(0, dp(8), 0, dp(4))
            }
            addView(
                LinearLayout(this@MainActivity).apply {
                    orientation = LinearLayout.VERTICAL
                    addView(statusText)
                    addView(modelText)
                },
                LinearLayout.LayoutParams(0, -2, 1f),
            )
            addView(chip("API demo"))
        }
    }

    private fun composer(): View {
        input = EditText(this).apply {
            hint = "Ask about the screenshot or a Pixel feature"
            setText("How do I update from here?")
            minLines = 1
            maxLines = 4
            textSize = 15f
            setTextColor(INK)
            setHintTextColor(MUTED)
            background = rounded(Color.WHITE, STROKE, dp(18).toFloat())
            setPadding(dp(14), dp(12), dp(14), dp(12))
        }
        imageStatus = text("No screenshot attached", 13f, MUTED, false)
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(Color.WHITE, STROKE, dp(22).toFloat())
            setPadding(dp(10), dp(10), dp(10), dp(8))
            addView(input, LinearLayout.LayoutParams(-1, -2))
            addView(
                LinearLayout(this@MainActivity).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    addView(imageStatus, LinearLayout.LayoutParams(0, -2, 1f))
                    addView(button("+", false) {
                        if (selectedImageUri == null) {
                            pickImage()
                        } else {
                            selectedImageUri = null
                            imageStatus.text = "No screenshot attached"
                        }
                    }, compactButtonParams())
                    addView(button("Mic", false) { requestVoice() }, compactButtonParams())
                    addView(button("Send", true) { send() }, compactButtonParams())
                },
            )
        }
    }

    private fun send() {
        val question = input.text.toString().trim()
        if (question.isEmpty()) return
        hideKeyboard()
        input.setText("")
        addMessage(true, question)
        addMessage(false, "Thinking...")
        scope.launch {
            runCatching {
                val client = connectClient()
                try {
                    val image = selectedImageUri?.let {
                        EssentialMediaAttachment(
                            kind = EssentialMediaKind.IMAGE,
                            uri = it.toString(),
                            mimeType = contentResolver.getType(it) ?: "image/*",
                        )
                    }
                    val audio = EssentialMediaAttachment(
                        kind = EssentialMediaKind.AUDIO,
                        mimeType = "audio/transcript",
                        metadata = mapOf("transcript" to question),
                    )
                    val references = listOf(
                        EssentialReferenceDocument(
                            title = "Pixel Demo Local Guide",
                            text = quickGuideText,
                            mimeType = "text/plain",
                            metadata = mapOf(
                                "source" to "bundled_demo_notes",
                                "offline" to "true",
                                "asset" to PIXEL_GUIDE_TEXT_ASSET,
                            ),
                        ),
                    )
                    val request = EssentialTaskRequest.pixelFeatureChat(
                        prompt = """
                            Answer in clear, practical English.
                            This demo app is an external Android app calling the Essential AI API on the same phone.
                            Web search and location context are enabled. If sources or location context are provided, use them as evidence and do not say web search is unavailable.
                            Shared memory is off in this demo. Do not treat older messages as the current request.
                            If a screenshot is attached, inspect it as a Pixel settings screen and give the next steps the user can follow from that screen.
                            Question: $question
                        """.trimIndent(),
                        image = image,
                        audio = audio,
                        references = references,
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
                            minContextWindow = 4096,
                        ),
                    ).copy(
                        attachments = listOfNotNull(image, audio),
                        maxTokens = 384,
                        timeoutMs = 90_000,
                    )
                    client.runTask(request)
                } finally {
                    client.close()
                }
            }.onSuccess { result ->
                latestAssistantText = cleanAssistantText(result.text.ifBlank { "No answer was returned." })
                replaceLastAssistant(latestAssistantText)
                speakLatest()
            }.onFailure { error ->
                latestAssistantText =
                    if (error.message?.contains("timed out", ignoreCase = true) == true) {
                        "Essential connected, but the request timed out. Try a shorter question."
                    } else {
                        "Error: ${error.message ?: error.javaClass.simpleName}"
                    }
                replaceLastAssistant(latestAssistantText)
            }
        }
    }

    private fun refreshModels() {
        scope.launch {
            runCatching {
                val client = connectClient()
                try {
                    client.models.list()
                } finally {
                    client.close()
                }
            }.onSuccess { models ->
                statusText.text = "Essential: connected"
                val installed = models.filter { it.isInstalled }
                modelText.text = if (installed.isEmpty()) {
                    "Web on / Location on / Shared memory off"
                } else {
                    "Models: ${installed.joinToString { it.modelId }}"
                }
            }.onFailure {
                statusText.text = "Essential: not connected"
                modelText.text = "Open Essential first"
            }
        }
    }

    private fun handleAutoRun(intent: Intent?) {
        val question = intent
            ?.getStringExtra(EXTRA_AUTO_RUN_PIXEL_HELP)
            ?.takeIf { it.isNotBlank() }
            ?: return
        input.setText(question)
        input.post { send() }
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

    private fun requestVoice() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_RECORD_AUDIO)
            return
        }
        startVoice()
    }

    private fun startVoice() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.US.toLanguageTag())
        }
        startActivityForResult(intent, REQUEST_SPEECH)
    }

    private fun pickImage() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, REQUEST_IMAGE)
    }

    private fun persistReadPermission(uri: Uri) {
        runCatching {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun addMessage(user: Boolean, body: String) {
        messages.add(user to body)
        renderMessages(scrollToBottom = true)
    }

    private fun replaceLastAssistant(body: String) {
        val index = messages.indexOfLast { !it.first }
        if (index >= 0) {
            messages[index] = false to body
        } else {
            messages.add(false to body)
        }
        latestAssistantView?.text = body
    }

    private fun renderMessages(scrollToBottom: Boolean) {
        messagesColumn.removeAllViews()
        latestAssistantView = null
        messages.forEach { (user, body) ->
            val view = bubble(user, body)
            if (!user) {
                latestAssistantView = view
            }
            messagesColumn.addView(view)
        }
        scroll.post {
            if (scrollToBottom) {
                scroll.fullScroll(View.FOCUS_DOWN)
            }
        }
    }

    private fun cleanAssistantText(value: String): String {
        return value
            .replace("`", "")
            .replace("**", "")
            .trim()
    }

    private fun bubble(user: Boolean, body: String): TextView {
        return TextView(this).apply {
            text = body
            textSize = 15f
            setTextColor(if (user) Color.WHITE else INK)
            setLineSpacing(3f, 1.08f)
            background = rounded(if (user) ACCENT else SURFACE, if (user) ACCENT else STROKE, dp(18).toFloat())
            setPadding(dp(14), dp(11), dp(14), dp(11))
            layoutParams = LinearLayout.LayoutParams((resources.displayMetrics.widthPixels * 0.80f).toInt(), -2).apply {
                gravity = if (user) Gravity.END else Gravity.START
                setMargins(0, dp(6), 0, dp(6))
            }
        }
    }

    private fun button(label: String, primary: Boolean, action: () -> Unit): Button {
        return Button(this).apply {
            text = label
            textSize = 14f
            isAllCaps = false
            setTextColor(if (primary) Color.WHITE else ACCENT)
            background = rounded(if (primary) ACCENT else Color.WHITE, ACCENT, dp(16).toFloat())
            setOnClickListener { action() }
        }
    }

    private fun chip(label: String): TextView {
        return text(label, 12f, GUIDE, true).apply {
            gravity = Gravity.CENTER
            background = rounded(GUIDE_BG, GUIDE, dp(14).toFloat())
            setPadding(dp(10), dp(6), dp(10), dp(6))
        }
    }

    private fun speakLatest() {
        val text = latestAssistantText.take(MAX_SPEECH_CHARS)
        if (text.isNotBlank()) {
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "pixel-chat")
        }
    }

    private fun readAssetText(name: String): String {
        return assets.open(name).bufferedReader(Charsets.UTF_8).use { it.readText() }
    }

    private fun text(value: String, size: Float, color: Int, bold: Boolean): TextView {
        return TextView(this).apply {
            text = value
            textSize = size
            setTextColor(color)
            if (bold) typeface = Typeface.DEFAULT_BOLD
            setLineSpacing(2f, 1.05f)
        }
    }

    private fun weightParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(0, dp(50), 1f).apply {
            setMargins(dp(4), dp(9), dp(4), 0)
        }
    }

    private fun compactButtonParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(dp(58), dp(44)).apply {
            setMargins(dp(6), dp(8), 0, 0)
        }
    }

    private fun rounded(fill: Int, stroke: Int, radius: Float): GradientDrawable {
        return GradientDrawable().apply {
            setColor(fill)
            cornerRadius = radius
            setStroke(dp(1), stroke)
        }
    }

    private fun hideKeyboard() {
        (getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager)
            .hideSoftInputFromWindow(input.windowToken, 0)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private companion object {
        const val PREFERRED_MODEL_ID = "gemma-4-e2b-it"
        const val REQUEST_RECORD_AUDIO = 10
        const val REQUEST_SPEECH = 11
        const val REQUEST_IMAGE = 12
        const val MAX_SPEECH_CHARS = 600
        const val PIXEL_GUIDE_TEXT_ASSET = "pixel_feature_guide.txt"
        const val EXTRA_AUTO_RUN_PIXEL_HELP = "autoRunPixelHelp"
        const val CANVAS = 0xFFF7F7F5.toInt()
        const val SURFACE = 0xFFF1F3F5.toInt()
        const val INK = 0xFF151A20.toInt()
        const val MUTED = 0xFF66717C.toInt()
        const val STROKE = 0xFFDAD5C8.toInt()
        const val ACCENT = 0xFF2251A4.toInt()
        const val GUIDE = 0xFF1E6D4A.toInt()
        const val GUIDE_BG = 0xFFE8F4EC.toInt()
    }
}
