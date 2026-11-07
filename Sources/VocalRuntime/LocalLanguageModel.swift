import Foundation
import llama

/// One local llama.cpp context, serialized on this actor. Nothing in the load or
/// generation path performs network I/O. Only the explicit setup method downloads.
public actor LocalLanguageModel {
    public static let identity = "LFM2.5-1.2B-Instruct Q4_K_M / llama.cpp b12018"
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var history: [(user: String, assistant: String)] = []
    private var evaluated: [llama_token] = []
    private var generating = false
    private static let instructions = """
    You are a calm, thoughtful AI companion having a private voice conversation.
    Speak directly to the person, like someone who is paying attention. Usually use one or
    two short sentences. Make your first sentence a brief, useful thought. Match the person's
    tone and what they actually want: company, ordinary chat, information, or advice.
    Use natural contractions. Be warm without pep talks, excessive reassurance, or therapy language.
    If they want company, stay in the conversation rather than trying to fix their feelings.
    Don't give instructions to breathe, relax, calm down, or do exercises unless they ask.
    Don't keep saying 'that sounds', 'I hear you', or 'I'm here'. A question is optional;
    ask one only when it gives the person something useful to respond to.
    Remember the facts they share. Answer factual follow-ups directly from the conversation.
    Don't invent details about them, trips, or personal experiences of your own.
    Output only the words to speak, without Markdown, lists, role labels, or stage directions.
    Be honest about being AI if asked. Do not diagnose or prescribe.

    Examples of tone, not scripts:
    Person: I don't want advice. I'm just tired.
    Reply: Okay, no advice. We can just talk for a bit.
    Person: Can we talk about something ordinary?
    Reply: Sure. Have you watched anything good lately?
    Person: I'm annoyed, not scared.
    Reply: Annoyed makes sense. What happened?
    """

    private static var systemPrefix: String { "<|im_start|>system\n\(instructions)<|im_end|>\n" }
    public private(set) var lastPromptTokens = 0
    public private(set) var lastReusedTokens = 0

    public init() {}
    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    public static func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try LocalStorage.prepare()
        try await LFMAssets.download(progress: progress)
    }

    public func load() throws {
        if model != nil { return }
        guard LFMAssets.installed else { throw VocalError.message("Download the LFM model once using Voice and settings, then prepare the offline conversation.") }
        // Suppress native diagnostic logs; these are not conversational telemetry.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
        var parameters = llama_model_default_params()
        parameters.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(LFMAssets.file.path, parameters) else {
            throw VocalError.message("LFM could not load its local model file.")
        }
        var options = llama_context_default_params()
        options.n_ctx = 4096
        options.n_batch = 512
        options.n_ubatch = 512
        options.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        options.n_threads_batch = options.n_threads
        guard let context = llama_init_from_model(model, options) else {
            llama_model_free(model)
            throw VocalError.message("Could not allocate the local LFM context.")
        }
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
    }

    /// Warm native prompt/decode kernels without retaining a pretend exchange.
    /// Leave only the reusable system prefix in the inference cache.
    public func prewarm() throws {
        try load()
        guard context != nil else { return }
        reset()
        let warm = try tokenize(Self.systemPrefix + "<|im_start|>user\nHello.<|im_end|>\n<|im_start|>assistant\n")
        try evaluate(warm)
        if let token = warm.last { try evaluate([token]) }
        reset()
        try evaluate(tokenize(Self.systemPrefix))
    }

    public func unload() {
        reset()
        if let context { llama_free(context); self.context = nil }
        if let model { llama_model_free(model); self.model = nil }
        vocab = nil
    }

    public func reset() {
        history.removeAll()
        evaluated.removeAll()
        if let context { llama_memory_clear(llama_get_memory(context), true) }
    }

    public nonisolated func streamResponse(to prompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.generate(prompt: prompt, continuation: continuation)
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func generate(prompt: String, continuation: AsyncThrowingStream<String, Error>.Continuation) throws {
        guard !generating, let context, let vocab else { throw VocalError.message("Load the local LFM model before talking.") }
        generating = true
        defer { generating = false }
        do {
            var tokens = try tokenize(render(prompt: prompt))
            // Keep complete recent turns within a bounded context. No disk memory.
            while tokens.count + 192 > 4096, !history.isEmpty {
                history.removeFirst()
                tokens = try tokenize(render(prompt: prompt))
            }
            guard tokens.count + 192 <= 4096 else { throw VocalError.message("That message exceeds the prototype's context limit. Try a shorter message.") }
            if !tokens.starts(with: evaluated) {
                llama_memory_clear(llama_get_memory(context), true)
                evaluated.removeAll()
            }
            var remaining = Array(tokens.dropFirst(evaluated.count))
            // A complete reply must leave a tail (normally EOG + the next user turn).
            if remaining.isEmpty {
                llama_memory_clear(llama_get_memory(context), true)
                evaluated.removeAll()
                remaining = tokens
            }
            lastPromptTokens = tokens.count
            lastReusedTokens = evaluated.count
            try evaluate(remaining)
            let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params())!
            defer { llama_sampler_free(sampler) }
            llama_sampler_chain_add(sampler, llama_sampler_init_top_k(50))
            llama_sampler_chain_add(sampler, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.08, 0, 0))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.5))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0..<UInt32.max)))
            // Penalize repetition in this reply, not facts in the person's prompt.
            var bytes = [UInt8]()
            var latest = ""
            for _ in 0..<160 {
                try Task.checkCancellation()
                let token = llama_sampler_sample(sampler, context, -1)
                if llama_vocab_is_eog(vocab, token) { break }
                bytes += try piece(token)
                // Do not emit a replacement character when a UTF-8 sequence spans tokens.
                if let text = String(bytes: bytes, encoding: .utf8) {
                    latest = text
                    continuation.yield(text)
                }
                var next = [token]
                let code = next.withUnsafeMutableBufferPointer {
                    llama_decode(context, llama_batch_get_one($0.baseAddress!, 1))
                }
                guard code == 0 else { throw VocalError.message("LFM generation failed (\(code)).") }
                evaluated.append(token)
            }
            guard !latest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw VocalError.message("LFM returned an empty reply. Try again.")
            }
            history.append((prompt, latest))
        } catch {
            reset()
            throw error
        }
    }

    private func evaluate(_ tokens: [llama_token]) throws {
        guard let context else { throw VocalError.message("LFM is not loaded.") }
        var offset = 0
        while offset < tokens.count {
            try Task.checkCancellation()
            var chunk = Array(tokens[offset..<min(offset + 512, tokens.count)])
            let code = chunk.withUnsafeMutableBufferPointer {
                llama_decode(context, llama_batch_get_one($0.baseAddress!, Int32($0.count)))
            }
            guard code == 0 else { throw VocalError.message("LFM prompt processing failed (\(code)).") }
            evaluated += chunk
            offset += chunk.count
        }
    }

    private func render(prompt: String) -> String {
        // Matches Liquid AI's text-only, no-tools template. The tokenizer adds BOS.
        func safe(_ text: String) -> String {
            text.replacingOccurrences(of: "<|", with: "< |")
        }
        var result = Self.systemPrefix
        for turn in history {
            result += "<|im_start|>user\n\(safe(turn.user))<|im_end|>\n"
            result += "<|im_start|>assistant\n\(safe(turn.assistant))<|im_end|>\n"
        }
        return result + "<|im_start|>user\n\(safe(prompt))<|im_end|>\n<|im_start|>assistant\n"
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocab else { throw VocalError.message("LFM tokenizer is not loaded.") }
        let length = Int32(text.utf8.count)
        let count = llama_tokenize(vocab, text, length, nil, 0, true, true)
        guard count != Int32.min else { throw VocalError.message("Input is too large to tokenize.") }
        var tokens = [llama_token](repeating: 0, count: Int(abs(count)))
        let actual = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), true, true)
        guard actual >= 0 else { throw VocalError.message("LFM tokenization failed.") }
        return Array(tokens.prefix(Int(actual)))
    }

    private func piece(_ token: llama_token) throws -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        var count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if count < 0 {
            buffer = [CChar](repeating: 0, count: Int(-count))
            count = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        guard count >= 0 else { throw VocalError.message("LFM token decoding failed.") }
        return buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }
    }
}
