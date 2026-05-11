# Mac Help Demo Source Notes

This demo app is designed to ingest short excerpts or summaries from Apple's
public Mac user-facing help material. Keep bundled content small, cite the
source page inside the app where appropriate, and refresh the corpus before
publishing.

Recommended corpus sections:

- First steps on macOS: desktop, Dock, Finder, Spotlight, Control Center.
- Window and app basics: switching apps, Mission Control, Split View.
- Files and storage: Finder, iCloud Drive, external drives, AirDrop.
- Accessibility and input: Dictation, Voice Control, keyboard shortcuts.
- Safety: Apple ID, Find My, software updates, privacy permissions.

Prompt policy for the demo:

- Answer in Japanese unless the user asks otherwise.
- Prefer concrete numbered steps.
- If the user attaches a screenshot, refer to visible UI only when the runtime
  confirms that vision is available.
- If the runtime cannot inspect the image, say what information is missing and
  ask for a short description.
