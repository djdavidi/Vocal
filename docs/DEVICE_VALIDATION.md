# Conversation validation

1. Run the Release app, let preparation finish, and note the output route and thermal conditions. Use the built-in speakers initially; Bluetooth adds route latency.
2. Start conversation. Test a brief greeting, a longer sentence, a pause mid-thought and an unfinished phrase. Confirm silence alone causes no reply. Use Send now if the detector waits too long.
3. Confirm replies play without gaps and listening resumes after playback. End conversation during listening, generation and playback; confirm it stays stopped. Backgrounding should also stop it.
4. Assess natural phrasing, pacing, pronunciation and whether replies follow the actual request. Share a name/date and ask for it later. A small language model can still produce generic or incorrect replies.
5. Export timing metadata. Separate typed turns and spoken turns: speech-end timing includes automatic pause detection and transcription finalization. Audible onset is an estimate; use an external recorder for acoustic verification.
6. Quit/reopen with all networking disabled and repeat. Installed assets are required; setup itself needs a connection.
7. Run longer sessions to check microphone restarts, memory, thermals and context trimming. The current heuristic uses a fixed microphone level threshold and does not provide voice interruption during playback.

## iPhone

Repeat these checks in a signed Release build on the physical iPhone 16 Pro. Mac timings are not a substitute. Full Xcode, a connected device and signing are required. No physical-device result is established for this version.
