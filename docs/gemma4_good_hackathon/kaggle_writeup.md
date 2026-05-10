# Essential Field Companion

## Motivation

I started Essential from a very practical frustration. I am a high school student building Android apps, and I kept running into the same problem: adding AI was easy in a demo, but difficult in a real app. Cloud APIs are powerful, but every chat response, summary, translation, screenshot explanation, or voice interaction becomes another paid request. For an individual developer, or for a free project built by volunteers, that changes what is possible.

Gemma changed the equation because it made useful on-device AI realistic. Google AI Edge Gallery showed that Gemma could run locally on a phone, but my experience as a developer exposed another gap. A model gallery is not the same as an assistant platform. In a real app, the difficult parts are not only "call the model." They are model delivery, failed downloads, storage pressure, long context, battery restrictions, background work, memory rules, speech timing, and giving other apps a simple way to use the model.

So Essential is not just a chatbot. It is my attempt to build the missing product and systems layer around Gemma: the small engineering decisions that make local AI usable when the network is weak, the device is busy, the audio is long, or another app wants AI without paying for a remote API.

## Problem 1: Model Download Is Not Just a Download Button

The first problem was obvious but important: multi-gigabyte models cannot be bundled inside a normal APK. Hosting them myself would create bandwidth cost, maintenance work, and licensing risk. Hugging Face is a better place to distribute model files, but gated models introduce a new problem. Non-technical users should not have to manually create access tokens, accept licenses in a browser, copy URLs, and paste secrets into an app.

Essential solves this with a download path inspired by Google AI Edge Gallery. When the selected model points to Hugging Face, the app first tries a normal request. If the model is gated, it starts an OAuth flow, receives a Hugging Face access token through the Android redirect, and retries the same download with authentication. If the account still needs license approval, Essential opens the model page so the user can accept the terms and retry.

The download manager itself is defensive. It supports partial downloads, checks received size, retries retryable network failures, and verifies SHA-256 before activating the file. The storage layer does not move a file directly into the installed model area. It downloads into staging, verifies it, activates it only after the check passes, and moves failed files into quarantine. It also has an `ensureCapacityFor` path that can delete older unpinned models when storage is too tight. This is not a flashy feature, but without it, local AI becomes unreliable before the user even reaches the model.

## Problem 2: Keeping a Model Warm Without Keeping the Phone Heavy Forever

On-device models have a different performance shape from cloud APIs. Loading the model is expensive, and users feel that delay immediately. But keeping every engine alive forever makes the app heavy when it should be idle.

Essential uses a small runtime cache around the LiteRT-LM engine. The runtime can warm up the selected model, reuse the active engine for follow-up calls, and release idle engines afterward. The important detail is that `releaseIdle` can keep the current model path while closing other cached engines. This means Essential can stay responsive for the next likely prompt without holding unnecessary model instances in memory.

I also added practical fallback behavior. Live generation tries GPU first, but if the LiteRT-LM runtime hits known GPU failures for text-only requests, it retries on CPU instead of treating the whole request as failed. Context tokens are also chosen from the actual request shape: short local greetings do not need the same budget as image or product-research prompts. This keeps simple prompts fast while leaving room for harder tasks.

## Problem 3: Long Meetings Break the Simple Prompt Pattern

Meeting audio was where the "just put it in the prompt" approach broke down. A real meeting transcript can easily exceed the useful context budget, especially after adding instructions for summaries, TODOs, translations, sentiment, mind maps, and follow-up questions.

Essential handles this by compressing the transcript before asking for the final meeting analysis. The app formats transcript segments into chunks. If the meeting is short, it sends the transcript directly. If it is long, each chunk is summarized with strict rules: keep decisions, TODOs, open questions, names, and timestamps; do not add guesses; stay short. If the combined chunk summaries are still too large, Essential collapses them again in groups until they fit inside the meeting prompt budget.

This sounds simple, but it solved a real mobile problem. Long audio should not fail just because the transcript is too large. The compression pipeline preserves the facts that matter for later tasks, then the final Gemma call works from a smaller structured version of the meeting. If a model call fails during chunk compression, the app falls back to a trimmed deterministic chunk rather than losing the whole meeting.

## Problem 4: Background Work Must Survive Normal Phone Behavior

Another unglamorous problem is that meetings take time. Transcription, summarization, translation, and structured analysis can continue after the user leaves the screen. Android may restrict background work, and a long process without visible status feels broken.

Essential uses a foreground meeting-processing service with a persistent notification and a partial wake lock. The app updates the notification stage while processing continues, then shows completion or failure notifications. It also resumes interrupted processing sessions by checking saved state on startup. This is the kind of implementation detail that users may never notice when it works, but it is essential for a meeting assistant. A three-minute demo can hide these issues; a real user cannot.

## Problem 5: Memory Should Be Useful, Not Invisible Data Collection

Shared Memory is one of the core ideas in Essential, but I did not want it to be a vague "the app remembers things" feature. In the code, memory is treated as a controlled tool. Chat and Live can build memory context for prompts, and after generation the app can summarize the current session and write useful memory in the background. But when memory is disabled for a chat or API request, it is a hard read/write gate: the request should not read memory, and it should not write new memory.

This matters for developers too. Through Essential AI System, another Android app can choose whether a request should use web search, Shared Memory, documents, speech output, or only local generation. The API is useful because it exposes the same optimized local layer instead of forcing every app to rebuild download handling, model loading, prompt limits, memory policy, and runtime fallback.

## Problem 6: Real-Time Speech Can Make the Answer Worse

Essential Live exposed a different kind of bug. Streaming text is good for the screen, but speech is not the same as text. My first approach tried to speak tokens almost as soon as they arrived. That made the assistant feel responsive in theory, but in practice it could sound like one word or fragment at a time. English and Japanese both suffered because the TTS engine was receiving pieces that were too small to sound natural.

The fix was to separate visual streaming from spoken output. Essential can still update the chat bubble while Gemma generates, but for Live TTS it now waits for the completed response and sends coherent text to the speech layer. I also raised the non-forced speech threshold so future streaming speech paths prefer sentence-like chunks instead of tiny fragments. This is a good example of a lesson I learned repeatedly in this project: the fastest implementation is not always the most usable implementation. For voice, a short delay is better than broken speech.

## Result

Essential Field Companion is built around Gemma, but the project is really about everything around the model. It downloads large gated models through a user-friendly Hugging Face flow. It stages and verifies files before activation. It keeps the current model warm while releasing idle engines. It compresses long meetings before final analysis. It uses a foreground service for background meeting work. It treats Shared Memory as a controlled tool, not an always-on black box. It exposes the same local AI layer to other Android apps.

These are ordinary engineering problems, but they are exactly the problems that decide whether on-device AI becomes useful outside a demo. My goal with Essential is to make Gemma feel less like a model file and more like a dependable Android AI system that developers, writers, creators, and everyday users can actually build on.
