import GoogleSignIn
import SwiftData
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var auth: GoogleAuthService
    // Assuming CalendarSyncService is injected as EnvironmentObject
    @EnvironmentObject private var syncService: CalendarSyncService
    @Environment(\.modelContext) private var modelContext

    @State private var errorMessage: String?
    
    // Settings
    @State private var targetCalendarId: String = CalendarSettings.shared.targetCalendarId
    @State private var pastDays: Int = CalendarSettings.shared.syncWindowDaysPast
    @State private var futureDays: Int = CalendarSettings.shared.syncWindowDaysFuture

    var body: some View {
        NavigationStack {
            Form {
                Section("Google Account") {
                    if let user = auth.currentUser {
                        Text("Logged in as: \(user.profile?.email ?? "Unknown")")
                        Button("Sign Out") {
                            auth.signOut()
                        }
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
                        .onChange(of: targetCalendarId) { _, newValue in
                            CalendarSettings.shared.targetCalendarId = newValue
                        }
                    Text("Current target for writes: \(targetCalendarId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Section("Sync Window") {
                    Stepper("Past: \(pastDays) days", value: $pastDays, in: 1...365)
                        .onChange(of: pastDays) { _, newValue in
                            CalendarSettings.shared.syncWindowDaysPast = newValue
                        }
                    Stepper("Future: \(futureDays) days", value: $futureDays, in: 1...365)
                        .onChange(of: futureDays) { _, newValue in
                            CalendarSettings.shared.syncWindowDaysFuture = newValue
                        }
                }
                
                Section("Actions") {
                    Button("Force Full Sync") {
                        Task {
                            do {
                                try await syncService.performFullSync()
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(syncService.isSyncing)
                    
                    if syncService.isSyncing {
                        ProgressView()
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
        }
        .onAppear {
             targetCalendarId = CalendarSettings.shared.targetCalendarId
             pastDays = CalendarSettings.shared.syncWindowDaysPast
             futureDays = CalendarSettings.shared.syncWindowDaysFuture
        }
    }
}