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
        language: String?
    ) async throws {
        // 1. Create two independent FluidAudio streaming providers
        micStreamingProvider = FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
        systemStreamingProvider = FluidAudioStreamingProvider(fluidAudioService: fluidAudioService)
        
        // 2. Connect both to the same local model
        try await micStreamingProvider?.connect(model: model, language: language)
        try await systemStreamingProvider?.connect(model: model, language: language)
        
        // 3. Start consuming events from both providers
        if let micProvider = micStreamingProvider {
            micEventTask = consumeEvents(from: micProvider, speaker: .user)
        }
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
                case .partial(let text):
                    // Update or append partial hypothesis
                    if let lastIndex = utterances.lastIndex(where: { $0.speaker == speaker && $0.isPartial }) {
                        utterances[lastIndex] = MeetingUtterance(speaker: speaker, text: text, timestamp: Date(), isPartial: true)
                    } else {
                        utterances.append(MeetingUtterance(speaker: speaker, text: text, timestamp: Date(), isPartial: true))
                    }
                case .error(_):
                    break // log it
                case .sessionStarted:
                    break
                }
            }
        }
    }
}
