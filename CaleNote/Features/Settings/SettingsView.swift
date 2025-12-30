import GoogleSignIn
import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    @EnvironmentObject private var syncService: CalendarSyncService
    @Environment(\.modelContext) private var modelContext

    @State private var errorMessage: String?
    
    // Settings
    @AppStorage("targetCalendarId") private var targetCalendarId: String = CalendarSettings.shared.targetCalendarId
    @AppStorage("syncWindowDaysPast") private var pastDays: Int = CalendarSettings.shared.syncWindowDaysPast
    @AppStorage("syncWindowDaysFuture") private var futureDays: Int = CalendarSettings.shared.syncWindowDaysFuture

    var body: some View {
        Form {
            Section("Google Account") {
                if let user = auth.currentUser {
                    Text("Logged in as: \(user.profile?.email ?? "Unknown")")
                    Button("Sign Out") {
                        auth.signOut()
                    }
                    .foregroundColor(.red)
                } else {
                    Button("Sign In with Google") {
                        Task {
                            do {
                                try await auth.signIn()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
            
            Section("Calendar Settings") {
                TextField("Target Calendar ID", text: $targetCalendarId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                Text("Current target for writes: \(targetCalendarId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section("Sync Window") {
                Stepper("Past: \(pastDays) days", value: $pastDays, in: 1...365)
                Stepper("Future: \(futureDays) days", value: $futureDays, in: 1...365)
            }
            
            Section("Actions") {
                Button {
                    Task {
                        do {
                            try await syncService.performFullSync()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                } label: {
                    HStack {
                        if syncService.isSyncing {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Text("Force Full Sync")
                    }
                }
                .disabled(syncService.isSyncing)
                
                Button("Reset Tokens") {
                    // Logic to clear sync tokens if needed
                }
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: targetCalendarId) { _, newValue in
            CalendarSettings.shared.targetCalendarId = newValue
        }
        .onChange(of: pastDays) { _, newValue in
            CalendarSettings.shared.syncWindowDaysPast = newValue
        }
        .onChange(of: futureDays) { _, newValue in
            CalendarSettings.shared.syncWindowDaysFuture = newValue
        }
    }
}
