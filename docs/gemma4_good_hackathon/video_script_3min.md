# 3-Minute Demo Video Script

Format: horizontal video. Show the Android device for most of the video, with short cuts to code only in the API section. Target length: 2:50-3:00.

## Core Story

Essential was created from my experience as a high school Android developer. Paid AI APIs are useful, but they are a serious barrier for individual developers, students, and volunteer projects. Gemma is an excellent open model, and Edge Gallery proves that it can run on a smartphone, but the app experience is still much more limited than Gemini. Essential adds the missing product layer around Gemma: chat, shared memory, live voice, meeting intelligence, web/location grounding, offline-friendly workflows, and an on-device AI API for other apps.

## 0:00-0:22 Opening

Visual: presenter, Essential home screen, then model management screen.

Narration:

> Hi, I am Kiichi Toyama, the developer of Essential. I built this app from my own experience as a high school Android developer. Today, adding AI to an app usually means using a paid API. That is powerful, but for individual developers, students, or volunteer projects, every generated answer can become a cost problem.

On-screen text:

```text
Essential
Gemma 4 on-device assistant and local AI API
```

## 0:22-0:48 Why Essential

Visual: briefly show Edge Gallery or model management, then switch to Essential home and a fast montage of Chat, Live, Meeting Assistant, and API demo.

Narration:

> Gemma is an amazing open model, and Edge Gallery is a great, innovative way to run it on a smartphone. But when I used it, I felt a gap. Compared with Gemini, the experience was limited: fewer practical workflows, less context, no full assistant layer, and no easy way for my own apps to use the model. Essential is my attempt to fix that and make Gemma useful even in offline or difficult environments.

## 0:48-1:27 Feature 1: Chat, Shared Memory, Browser, and Location

Visual: open Essential Chat. Show a short greeting, then a location/weather question with web or browser grounding.

Demo prompt 1:

```text
Hello!
```

Expected short answer:

```text
Hello! How can I help you today?
```

Demo prompt 2:

```text
What is the weather forecast for my current location?
```

Narration:

> The first feature is the basic chat screen. It may look like a simple model demo, but Essential adds real assistant features around Gemma. Shared Memory helps generation stay consistent across chats and over time. The in-app browser and web research tools can bring in current information, and location context can be used when the user allows it. When network access is not available, the core assistant can still work from the local model and saved context.

On-screen text:

```text
Chat + Shared Memory + Browser + Location
Online when useful, local when needed
```

## 1:27-1:59 Feature 2: Meeting Assistant

Visual: open Meeting Assistant with prepared audio. Show transcript, summary, TODO, sentiment, mind map, translation, and Ask.

Narration:

> The second feature is Meeting Assistant. It can transcribe audio with Whisper, then use Gemma to create a summary, TODO list, sentiment analysis, mind map, translation, and follow-up answers. These outputs can also be written into Shared Memory. This is useful for school projects, app planning, volunteer meetings, and demanding work sites where people need reliable notes even when the network is poor.

Follow-up prompt:

```text
What are the most important next actions from this meeting?
```

On-screen text:

```text
Transcript
Summary
TODO
Sentiment
Mind map
Translation
Ask about the meeting
```

## 1:59-2:23 Feature 3: Essential Live

Visual: open Essential Live. Ask a short spoken question.

Speak to phone:

```text
Explain what Essential can do in one short sentence.
```

Narration:

> The third feature is Essential Live. It uses Android speech APIs so the user can talk with the AI instead of typing. Essential Live can use the same assistant capabilities as chat, including Shared Memory, web grounding, and location context. This matters when typing is inconvenient: walking outside, carrying equipment, working in a noisy place, or using the phone with only one hand.

On-screen text:

```text
Essential Live
Voice conversation with the same assistant layer
```

## 2:23-2:53 Feature 4: Essential AI System

Visual: show code snippet, then Pixel Feature Chat demo app calling Essential.

Narration:

> The final feature is the most innovative one: Essential AI System. Other Android apps can complete AI tasks on device by calling Essential. With only a few lines of code, a developer can use a free, powerful local AI layer instead of building the whole runtime alone. The caller can control web search, Shared Memory, model preference, spoken output, and reference documents.

On-screen code focus:

```kotlin
val client = EssentialClient.connect(context, serviceConfig)
val request = EssentialTaskRequest.pixelFeatureChat(
    prompt = "How do I use this Pixel feature?",
    image = screenshot,
    runtimeOptions = EssentialRuntimeOptions(
        webSearchEnabled = true,
        sharedMemoryReadEnabled = false,
        spokenOutputEnabled = true,
    ),
)
val result = client.runTask(request)
```

Demo prompt in Pixel Feature Chat:

```text
How do I use this Pixel feature?
```

Narration continuation:

> As a use case, this Pixel Feature Chat app sends a screenshot and question to Essential, then receives an answer generated by Gemma. Essential is not only an app. It is also a local AI platform for Android developers.

## 2:53-3:00 Closing

Visual: quick montage of Chat, Meeting Assistant, Live, and Pixel Feature Chat.

Narration:

> Essential makes Gemma closer to a real mobile assistant: useful for developers, writers, and everyday users, and reliable when paid APIs or network access are not the right answer.

On-screen final text:

```text
Essential
On-device Gemma 4 assistant
Local AI API for Android apps
```
