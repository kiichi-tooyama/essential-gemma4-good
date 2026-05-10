# Essential Field Companion Submission Pack

Essential Field Companion is an Android edge-AI app for the Gemma 4 Good
Hackathon. The project target is:

> For the most compelling and effective use case built using Google AI Edge's
> LiteRT implementation of Gemma 4.

## Main Message

Essential turns an Android phone into a private field companion powered by
Gemma 4 LiteRT-LM. It starts like a simple chat app, then adds web search,
current-location context, shared memory, voice conversation, meeting notes, and
external app access through an SDK-like API.

The demo should strongly show the API point. The Pixel AI Chat demo app is a
separate Android app that calls Essential as an on-device AI service. It proves
that other apps can use the same text, image, voice, web, location, reference
document, shared-memory control, and spoken-output features.

## Submission Files

- `kaggle_writeup.md`: main English writeup.
- `kaggle_fields.md`: short fields for the Kaggle form.
- `video_script_3min.md`: final English 3-minute demo script.
- `demo_test_script.md`: device test checklist before recording.
- `public_repo_readme.md`: public GitHub README draft.
- `developer_implementation_guide.md`: implementation-level reviewer guide.
- `sdk_external_integration_guide.md`: guide for calling Essential from other
  Android apps.
- `device_test_report.md`: local verification report template/results.

## Current Video Flow

1. Show Essential Chat as a normal chat app.
2. Ask a current-location weather question to show web and location grounding.
3. Explain shared memory for consistent answers across long use.
4. Show Essential Live voice conversation.
5. Show Meeting Assistant: transcript, summary, TODO, sentiment, translation,
   mind map, and follow-up Q&A.
6. Open Pixel AI Chat and show another app calling Essential through the local
   API.

## Technical Claims To Verify Before Upload

- Gemma 4 LiteRT-LM is installed and selected for chat and Live generation.
- Android `SpeechRecognizer` is used for live on-device speech recognition.
- MeloTTS is the selected speech-output model family; Android TTS is only a
  playback fallback when exported MeloTTS assets are missing.
- External Android SDK calls can send text, images, audio/transcripts, and
  reference documents, then receive text or spoken responses.
- Pixel AI Chat demo app installs and can call the Essential service.
- Optional web search and current-location context work on a real device.
