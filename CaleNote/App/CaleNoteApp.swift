import GoogleSignIn
import SwiftData
import SwiftUI

@main
struct CaleNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(for: [JournalEntry.self])
    }
}
