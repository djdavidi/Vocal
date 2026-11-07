import SwiftUI
import VocalCore
import VocalRuntime

struct ContentView: View {
    @Bindable var controller: ConversationController
    @State private var showingSettings = false
    @State private var showingTiming = false
    private var completed: [TurnMetrics] { controller.metrics.filter { $0.status == "complete" && $0.mode.contains("conversation") } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Let’s talk.").font(.largeTitle.bold())
                    Text("A calm voice, entirely offline.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Label(controller.phase.rawValue, systemImage: controller.phase == .listening ? "mic.fill" : "waveform")
                            .font(.title3.bold())
                        Text(controller.status).font(.callout).foregroundStyle(.secondary)
                        if controller.phase == .setup || controller.phase == .loading || controller.phase == .startingMic {
                            ProgressView().controlSize(.small)
                        }
                        controls
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
                    if !controller.userText.isEmpty { textBlock("You", text: controller.userText) }
                    if !controller.responseText.isEmpty {
                        textBlock("Companion", text: controller.responseText)
                    }
                    HStack {
                        TextField("Or type a message", text: $controller.typedPrompt)
                            .textFieldStyle(.roundedBorder).disabled(!controller.canTalk)
                            .onSubmit { controller.sendTypedPrompt() }
                        Button("Send") { controller.sendTypedPrompt() }
                            .disabled(!controller.canTalk || controller.typedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    DisclosureGroup("Voice and settings", isExpanded: $showingSettings) {
                        VStack(alignment: .leading, spacing: 12) {
                            if !controller.availableVoices.isEmpty {
                                Picker("Voice", selection: Binding(get: { controller.voiceID }, set: { controller.setVoice($0) })) {
                                    ForEach(controller.availableVoices) { Text($0.name).tag($0.id) }
                                }.disabled(!controller.idle)
                            }
                            Text("Phonon speaks. LFM replies. Audio and conversation stay on this device.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Install / repair offline models") { controller.downloadAssets() }.disabled(!controller.idle)
                            Button("Prepare offline conversation") { controller.prepareOffline() }.disabled(!controller.idle)
                            if let seconds = controller.loadSeconds {
                                Text(String(format: "Preparation: %.2f seconds (separate from reply timing)", seconds)).font(.caption)
                            }
                            Button("New conversation") { controller.newConversation() }.disabled(!controller.idle)
                            if !controller.responseText.isEmpty {
                                Button("Replay last reply") { controller.replayLastReply() }.disabled(!controller.idle)
                            }
                        }.padding(.top, 12)
                    }
                    DisclosureGroup("Response timing", isExpanded: $showingTiming) {
                        timing.padding(.top, 12)
                    }
                }.padding(24)
            }
            .navigationTitle("Vocal")
        }
        .task { controller.prepareOffline() }
    }

    @ViewBuilder private var controls: some View {
        if controller.phase == .listening {
            Text("I’ll reply after a pause, then listen again.").font(.caption).foregroundStyle(.secondary)
            Button("Send now") { controller.sendTurn() }.buttonStyle(.bordered)
        } else if controller.idle {
            Button("Start conversation") { controller.startConversation() }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!controller.canTalk)
        }
        if !controller.idle || controller.automaticConversation {
            Button(controller.automaticConversation ? "End conversation" : "Stop", role: .destructive) { controller.stop() }
                .disabled(controller.phase == .stopping)
        }
    }

    private func textBlock(_ label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            Text(text).textSelection(.enabled)
        }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let latest = completed.last {
                metric("Speech end → estimated audio", ms: latest.speechToAudioMS)
                metric("Reply request → estimated audio", ms: latest.buttonToAudioMS)
                metric("Reply request → first text", ms: latest.firstModelText.map { ($0 - latest.sendTime) * 1000 })
                metric("Reply request → first spoken phrase", ms: latest.firstSpeechSegment.map { ($0 - latest.sendTime) * 1000 })
                Text("Playback gaps: \(latest.playbackGaps)").font(.caption)
            }
            let warm = completed.filter { $0.warm && $0.voice == controller.voiceID }.compactMap(\.buttonToAudioMS)
            metric("Warm reply median (\(warm.count) turns)", ms: TurnMetrics.percentile(warm, fraction: 0.5))
            metric("Warm reply p95", ms: TurnMetrics.percentile(warm, fraction: 0.95))
            Text("Speech-end timing includes the automatic pause. Audible onset is estimated from rendering and output latency. These are Mac timings, not iPhone measurements.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Prepare timing report") { controller.exportMetrics() }
            if let url = controller.exportURL { ShareLink("Share timing report", item: url) }
        }
    }

    private func metric(_ label: String, ms: Double?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(ms.map { String(format: "%.0f ms", $0) } ?? "—").monospacedDigit()
        }.font(.caption)
    }
}
