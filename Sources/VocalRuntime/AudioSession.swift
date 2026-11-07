import AVFoundation

enum AudioSession {
    static func permission() async -> Bool {
        #if os(iOS)
        return await AVAudioApplication.requestRecordPermission()
        #else
        return await AVCaptureDevice.requestAccess(for: .audio)
        #endif
    }
    static func activate() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setPreferredIOBufferDuration(0.01)
        try session.setActive(true)
        #endif
    }
    static var route: String {
        #if os(iOS)
        return AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portType.rawValue }.joined(separator: "+")
        #else
        return "Mac audio (not an iPhone benchmark)"
        #endif
    }
}
