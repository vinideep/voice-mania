import SwiftUI
import SwiftData

struct MeetingWorkspaceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingSession.startTime, order: .reverse) private var meetings: [MeetingSession]
    
    @State private var selectedMeeting: MeetingSession?
    @State private var searchText = ""
    
    var filteredMeetings: [MeetingSession] {
        if searchText.isEmpty {
            return meetings
        } else {
            return meetings.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(filteredMeetings, selection: $selectedMeeting) { meeting in
                NavigationLink(value: meeting) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title)
                            .font(.headline)
                            .lineLimit(1)
                        
                        Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor(for: meeting.status))
                                .frame(width: 8, height: 8)
                            Text(meeting.status.capitalized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contextMenu {
                    Button(role: .destructive) {
                        modelContext.delete(meeting)
                        if selectedMeeting == meeting {
                            selectedMeeting = nil
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Meetings")
            .searchable(text: $searchText, prompt: "Search meetings...")
            .listStyle(.sidebar)
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                ContentUnavailableView(
                    "No Meeting Selected",
                    systemImage: "person.2.wave.2",
                    description: Text("Select a meeting from the sidebar to view its AI summary and transcript.")
                )
            }
        }
    }
    
    private func statusColor(for status: String) -> Color {
        switch status {
        case "recording": return .red
        case "summarizing": return .orange
        case "completed": return .green
        case "failed": return .red
        default: return .gray
        }
    }
}

struct MeetingDetailView: View {
    @Bindable var meeting: MeetingSession
    @State private var selectedTab: Tab = .summary
    
    enum Tab {
        case summary, transcript
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                TextField("Meeting Title", text: $meeting.title)
                    .font(.largeTitle.bold())
                    .textFieldStyle(.plain)
                
                HStack(spacing: 12) {
                    Label(meeting.startTime.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                    Text("•")
                    Label(formatDuration(meeting.totalDuration), systemImage: "clock")
                }
                .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Picker
            Picker("View", selection: $selectedTab) {
                Text("AI Summary").tag(Tab.summary)
                Text("Transcript").tag(Tab.transcript)
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Content
            ScrollView {
                VStack(alignment: .leading) {
                    if selectedTab == .summary {
                        if let summary = meeting.summary {
                            Text(LocalizedStringKey(summary))
                                .textSelection(.enabled)
                        } else if meeting.status == "summarizing" {
                            VStack(spacing: 16) {
                                ProgressView()
                                Text("Ollama is generating your meeting summary...")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                        } else {
                            Text("No summary available.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        if let transcript = meeting.fullTranscript {
                            Text(transcript)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        } else {
                            Text("No transcript available.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(AppTheme.Surface.window)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
}
