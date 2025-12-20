//
//  CaleNoteApp.swift
//  CaleNote
//
//  Created by Masaya Kawai on 2025/12/20.
//

import SwiftUI
import SwiftData

@main
struct CaleNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            JournalEntry.self
        ])
    }
}

