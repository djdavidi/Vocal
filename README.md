# Vocal: offline conversation on Mac

Phonon 31M speaks supplied voices; LFM2.5-1.2B generates replies; Apple SpeechAnalyzer transcribes locally. No voice-cloning controls, cloud inference, accounts, or conversation storage.

## Run

Apple Silicon, macOS 26+, and command-line developer tools are required. The Mac app does not require Apple Intelligence or full Xcode.

Close Vocal before rebuilding:

```sh
zsh scripts/build-mac.sh
open dist/Vocal.app
```

The app loads and silently warms local models on launch. If assets are missing, expand **Voice and settings → Install / repair offline models** while online. Installation downloads the verified LFM and Phonon assets and English speech-recognition assets. Later conversation paths use local files.

## Conversation

Press **Start conversation**, then speak normally. Stable transcription plus a short silence triggers a reply. The microphone closes while Phonon speaks and reopens automatically after playback. **Send now** bypasses the pause; **End conversation** stops audio and clears context. Typed messages are available while idle. Backgrounding also stops the session.

The pause policy waits about 0.65 seconds after terminal punctuation, 0.85 seconds otherwise, or 1.35 seconds after an unfinished phrase. Transcription must be stable for 0.25 seconds and the microphone must have detected speech-level audio. This is a level/text heuristic: noise, quiet speech, and mid-thought pauses can affect it. It does not support interrupting spoken replies with your voice yet.

LFM uses short conversational replies, recent in-memory context, and a reusable prompt cache. Phonon starts from a complete sentence or useful initial clause while later text is still being generated, then streams 80 ms audio frames. Juniper is the default supplied voice; settings retain the selected voice across launches.

## Timing

Expand **Response timing** for speech-end to estimated audible speech, request-to-text/audio, playback gaps and warm median/p95. Speech-end timing includes the automatic pause. PCM availability is earlier than heard speech; audible onset uses render timing, leading silence and output-route latency rather than an acoustic loopback. Exported reports contain timing metadata without conversation text/audio.

Preparation is shown separately and includes silent warm-up; it remains part of startup cost. Mac measurements do not predict iPhone performance.

## Verification

```sh
swift run -c release --disable-sandbox VocalCoreChecks
swift run -c release --disable-sandbox VocalEngineCheck --conversation --prewarm --label tuned
```

The engine diagnostic writes synthetic prompts, replies and timing to `conversation-output/`. It runs LFM through Phonon without microphone input or playback, so its first-PCM result is not end-to-end spoken latency. Add `--download` only to install missing model assets.

## Assets and dependencies

- Phonon `ptts` v0.6.0 with its SHA-256-verified official Core ML bundle and supplied voices.
- LFM Q4_K_M, official revision `8ed288026e23958ad9dfa92d53ed773a8eee7125`, SHA-256 `b1b3de114215d9507409a662a501a631095a479a419584e8a2ded6304b19b4f5`, via llama.cpp b12018.
- ZIPFoundation extracts the verified Phonon archive.

Kokoro and FluidAudio are removed from runtime and dependencies. Old prototype model files are unused and remain on disk. Models live in app-specific Application Support and are excluded from backups. Microphone buffers, conversation history and playback remain in memory.

This Mac app is a local development bundle. Keep the repository and `.build` directory in place because SwiftPM resource accessors can use their build-directory fallback.

`Vocal.xcodeproj` is the physical iPhone target, requiring full Xcode and signing. No iPhone build or performance result has been established. The llama.cpp framework has no Simulator slice. See `docs/VERIFICATION.md` and `docs/DEVICE_VALIDATION.md` for evidence and remaining checks.
