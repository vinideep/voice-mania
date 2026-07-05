import Foundation
import os
import SwiftData

struct MeetingUtterance: Identifiable, Sendable {
    let id = UUID()
    let speaker: Speaker
    let text: String
    let timestamp: Date
    let isPartial: Bool  // partial (hypothesis) vs committed (confirmed)
    
    enum Speaker: String, Sendable {
        case user = "You"
        case others = "Others"
    }
}

@MainActor
class MeetingTranscriptManager: ObservableObject {
    @Published var utterances: [MeetingUtterance] = []
    @Published var isActive = false
    
    var onUtteranceUpdate: ((String) -> Void)?
    
    private let meetingAudioService = MeetingAudioCaptureService()
    private var micStreamingProvider: FluidAudioStreamingProvider?
    private var systemStreamingProvider: FluidAudioStreamingProvider?
    private var micEventTask: Task<Void, Never>?
    private var systemEventTask: Task<Void, Never>?
    
    /// Full committed transcript for AI summarization
    var fullTranscript: String {
        utterances
            .filter { !$0.isPartial }
            .map { "[\($0.speaker.rawValue)]: \($0.text)" }
            .joined(separator: "\n")
    }
    
    func startMeeting(
        fluidAudioService: FluidAudioTranscriptionService,
        model: any TranscriptionModel,
        language: String?,
        captureMicrophone: Bool = true
    ) async throws {
        // 1. Create independent FluidAudio streaming providers
        if captureMicrophone {
            micStreamingProvider = FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
            try await micStreamingProvider?.connect(model: model, language: language)
            
            if let micProvider = micStreamingProvider {
                micEventTask = consumeEvents(from: micProvider, speaker: .user)
            }
        }
        
        systemStreamingProvider = FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
        try await systemStreamingProvider?.connect(model: model, language: language)
        
        if let sysProvider = systemStreamingProvider {
            systemEventTask = consumeEvents(from: sysProvider, speaker: .others)
        }
        
        // 4. Start system audio capture, feeding chunks to provider B
        meetingAudioService.onAudioChunk = { [weak self] data in
            Task { try? await self?.systemStreamingProvider?.sendAudioChunk(data) }
        }
        try await meetingAudioService.startCapture()
        
        isActive = true
    }
    
    func stopMeeting() async -> String {
        // Commit both streams and collect final text
        try? await micStreamingProvider?.commit()
        try? await systemStreamingProvider?.commit()
        
        await meetingAudioService.stopCapture()
        
        micEventTask?.cancel()
        systemEventTask?.cancel()
        
        await micStreamingProvider?.disconnect()
        await systemStreamingProvider?.disconnect()
        
        isActive = false
        return fullTranscript
    }
    
    /// Feed mic audio chunks (called by CoreAudioRecorder.onAudioChunk)
    func feedMicChunk(_ data: Data) {
        Task { try? await micStreamingProvider?.sendAudioChunk(data) }
    }
    
    private func consumeEvents(from provider: FluidAudioStreamingProvider, speaker: MeetingUtterance.Speaker) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in provider.transcriptionEvents {
                switch event {
                case .committed(let text):
                    utterances.append(MeetingUtterance(speaker: speaker, text: text, timestamp: Date(), isPartial: false))
                    notifyUpdate()
                case .partial(let text):
                    // Update or append partial hypothesis
                    if let lastIndex = utterances.lastIndex(where: { $0.speaker == speaker && $0.isPartial }) {
                        utterances[lastIndex] = MeetingUtterance(speaker: speaker, text: text, timestamp: Date(), isPartial: true)
                    } else {
                        utterances.append(MeetingUtterance(speaker: speaker, text: text, timestamp: Date(), isPartial: true))
                    }
                    notifyUpdate()
                case .error(_):
                    break // log it
                case .sessionStarted:
                    break
                }
            }
        }
    }
    
    private func notifyUpdate() {
        // Send the last 3 utterances to keep the floating UI clean
        let recent = utterances.suffix(3)
        let text = recent.map { "[\($0.speaker.rawValue)] \($0.text)" }.joined(separator: "\n")
        onUtteranceUpdate?(text)
    }
}
