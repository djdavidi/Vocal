# Verification — October 31, 2026

Current build uses Phonon/Juniper and LFM2.5-1.2B Q4_K_M. Kokoro/FluidAudio and voice cloning are removed from active code/dependencies. Local assets were already installed and SHA-256 verified during setup.

## Automated checks

All eight core checks pass: cumulative text without duplicate speech; final partial flush; long-sentence early start; latency boundaries; unknown speech-end handling; useful first-clause streaming; abbreviation/decimal boundaries; and stable-text/speech/pause requirements for automatic turns.

## LFM → Phonon diagnostic

Apple M5 MacBook Air, 16 GB, macOS 26.5.1. Eight sequential synthetic conversational turns, with cached context and silent preparation warm-up. No microphone or playback. First PCM is not audible latency.

| Turn | First text | First PCM |
| --- | ---: | ---: |
| Company without advice | 118 ms | 185 ms |
| Ordinary conversation | 29 ms | 103 ms |
| Brief octopus fact | 28 ms | 125 ms |
| Sister visiting | 82 ms | 126 ms |
| Recall name and date | 34 ms | 86 ms |
| No breathing/relaxation advice | 82 ms | 156 ms |
| Annoyed rather than anxious | 76 ms | 104 ms |
| Request a short reply | 37 ms | 64 ms |

Result: about 64–185 ms first PCM, median about 114 ms, across this single eight-turn diagnostic. The reusable prefix contained 314–573 tokens. Full synthetic prompts/replies and exact timings are in local `conversation-output/tuned.json`.

The tuned run correctly recalled Maya visiting Friday and avoided the expressly unwanted advice. Quality remains uneven: it still asked how the day had been after the person said it was long, and responded generically to the correction about annoyance. This is evidence of improved behavior on this small sample, not a quality guarantee or a statistical performance benchmark.

## Automatic conversation

The controller now uses stable text and 0.65–1.35 seconds of level-detected silence, disables microphone capture during response playback, waits another 150 ms for speaker tail, and reopens input. Send now and End conversation remain available. A fixed level threshold is not semantic voice activity detection; noise and very quiet speech require real-world listening tests.

Complete live-microphone conversation quality, disconnected-network restart, extended-session stability and iPhone performance still require validation. Timings above exclude transcription finalization, pause detection and audible playback.

## Native app check

The Release app loaded local assets, generated and spoke a synthetic typed reply about the Moon, and returned to Ready. Estimated audible onset was 303 ms after request (129 ms first text, 244 ms first phrase), with zero playback gaps. One observation, not a benchmark.

Starting automatic input returned the microphone-permission error; macOS denies microphone access to Vocal on this machine. Full automatic spoken turns could not be exercised. Enable Vocal under System Settings → Privacy & Security → Microphone before live testing.
