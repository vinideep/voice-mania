import Foundation
import ScreenCaptureKit
import AVFoundation
import os

final class MeetingAudioCaptureService: NSObject, @unchecked Sendable {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MeetingAudioCapture")
    
    private var stream: SCStream?
    private(set) var isCapturing = false
    
    /// Audio chunk callback — same signature as CoreAudioRecorder.onAudioChunk
    /// Delivers 16kHz mono Int16 PCM data
    var onAudioChunk: ((_ data: Data) -> Void)?
    
    func startCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw MeetingAudioError.noDisplay
        }
        
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16000       // Match CoreAudioRecorder
        config.channelCount = 1         // Mono
        config.excludesCurrentProcessAudio = true  // Don't capture VoiceInk's own sounds
        
        // Capture entire display audio (covers Zoom, Chrome, Teams, etc.)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream?.addStreamOutput(
            self, type: .audio,
            sampleHandlerQueue: DispatchQueue(label: "meeting-system-audio", qos: .userInteractive)
        )
        
        try await stream?.startCapture()
        isCapturing = true
        logger.notice("System audio capture started")
    }
    
    func stopCapture() async {
        guard isCapturing else { return }
        try? await stream?.stopCapture()
        stream = nil
        isCapturing = false
        logger.notice("System audio capture stopped")
    }
}

extension MeetingAudioCaptureService: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let onAudioChunk = onAudioChunk else { return }
        
        // Extract PCM samples from CMSampleBuffer → convert to Int16 Data
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription),
              let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        
        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let status = CMBlockBufferGetDataPointer(blockBuffer,
                                                 atOffset: 0,
                                                 lengthAtOffsetOut: &lengthAtOffset,
                                                 totalLengthOut: &totalLength,
                                                 dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return }
        
        // SCStream audio is typically Float32 interleaved
        if audioFormat.commonFormat == .pcmFormatFloat32 {
            let floatPointer = dataPointer.withMemoryRebound(to: Float32.self, capacity: totalLength / MemoryLayout<Float32>.size) { $0 }
            let frameCount = totalLength / (MemoryLayout<Float32>.size * Int(audioFormat.channelCount))
            
            var int16Samples = [Int16](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                // If stereo, mix to mono
                var sample: Float32 = 0.0
                for c in 0..<Int(audioFormat.channelCount) {
                    sample += floatPointer[i * Int(audioFormat.channelCount) + c]
                }
                sample /= Float32(audioFormat.channelCount)
                
                // Convert to Int16 and clamp
                var intSample = sample * 32767.0
                intSample = max(-32768.0, min(32767.0, intSample))
                int16Samples[i] = Int16(intSample)
            }
            
            let data = int16Samples.withUnsafeBufferPointer { Data(buffer: $0) }
            onAudioChunk(data)
        } else if audioFormat.commonFormat == .pcmFormatInt16 {
            let int16Pointer = dataPointer.withMemoryRebound(to: Int16.self, capacity: totalLength / MemoryLayout<Int16>.size) { $0 }
            let frameCount = totalLength / (MemoryLayout<Int16>.size * Int(audioFormat.channelCount))
            
            var monoSamples = [Int16](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                var sample: Int32 = 0
                for c in 0..<Int(audioFormat.channelCount) {
                    sample += Int32(int16Pointer[i * Int(audioFormat.channelCount) + c])
                }
                sample /= Int32(audioFormat.channelCount)
                monoSamples[i] = Int16(sample)
            }
            
            let data = monoSamples.withUnsafeBufferPointer { Data(buffer: $0) }
            onAudioChunk(data)
        }
    }
}

enum MeetingAudioError: LocalizedError {
    case noDisplay
    var errorDescription: String? { "No display found for audio capture" }
}
