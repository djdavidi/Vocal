import SwiftUI
import VocalRuntime
#if os(macOS)
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: ConversationController?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller else { return .terminateNow }
        Task {
            await controller.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif

@main
struct VocalApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    #endif
    @State private var controller = ConversationController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .frame(minWidth: 360, idealWidth: 520, minHeight: 600)
                #if os(macOS)
                .onAppear { delegate.controller = controller }
                #endif
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { controller.stop() }
                }
        }
    }
}
