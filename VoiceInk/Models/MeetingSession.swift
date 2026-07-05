import Foundation
import SwiftData

@Model
final class MeetingSession {
    var id: UUID = UUID()
    var title: String = "Untitled Meeting"
    var startTime: Date = Date()
    var endTime: Date?
    var totalDuration: TimeInterval = 0
    var status: String = "recording"  // recording | summarizing | completed | failed
    
    /// Full speaker-labeled transcript: "[You]: ...\n[Others]: ..."
    var fullTranscript: String?
    
    /// AI-generated summary (Markdown) from Ollama
    var summary: String?
    
    /// Detected meeting app name
    var meetingApp: String?
    
    init(title: String = "Untitled Meeting") {
        self.id = UUID()
        self.title = title
        self.startTime = Date()
    }
}
