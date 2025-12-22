//
//  ConflictResolutionService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/22.
//
import Foundation
import SwiftData

@MainActor
final class ConflictResolutionService {

    enum Resolution {
        case useLocal   // ローカル版を採用してカレンダーに再送
        case useRemote  // カレンダー版を採用してローカルを上書き
    }

    /// 競合を解決する
    func resolveConflict(
        entry: JournalEntry,
        resolution: Resolution,
        targetCalendarId: String,
        auth: GoogleAuthService,
        modelContext: ModelContext
    ) async throws {

        guard entry.hasConflict else {
            throw ConflictResolutionError.noConflict
        }

        switch resolution {
        case .useLocal:
            try await resolveWithLocal(
                entry: entry,
                targetCalendarId: targetCalendarId,
                auth: auth,
                modelContext: modelContext
            )

        case .useRemote:
            try await resolveWithRemote(
                entry: entry,
                modelContext: modelContext
            )
        }

        // 競合状態をクリア
        clearConflictState(entry: entry)
        try modelContext.save()
    }

    private func resolveWithLocal(
        entry: JournalEntry,
        targetCalendarId: String,
        auth: GoogleAuthService,
        modelContext: ModelContext
    ) async throws {
        // ローカル版を採用してカレンダーに再送
        let syncService = JournalCalendarSyncService()
        entry.needsCalendarSync = true
        try await syncService.syncOne(
            entry: entry,
            targetCalendarId: targetCalendarId,
            auth: auth,
            modelContext: modelContext
        )
    }

    private func resolveWithRemote(
        entry: JournalEntry,
        modelContext: ModelContext
    ) async throws {
        // カレンダー版を採用してローカルに適用
        guard let remoteTitle = entry.conflictRemoteTitle,
              let remoteBody = entry.conflictRemoteBody,
              let remoteEventDate = entry.conflictRemoteEventDate,
              let remoteUpdatedAt = entry.conflictRemoteUpdatedAt
        else {
            throw ConflictResolutionError.missingRemoteData
        }

        entry.title = remoteTitle.isEmpty ? nil : remoteTitle
        entry.body = remoteBody
        entry.eventDate = remoteEventDate
        entry.updatedAt = Date()
        entry.linkedEventUpdatedAt = remoteUpdatedAt
        entry.needsCalendarSync = false
    }

    private func clearConflictState(entry: JournalEntry) {
        entry.hasConflict = false
        entry.conflictDetectedAt = nil
        entry.conflictRemoteTitle = nil
        entry.conflictRemoteBody = nil
        entry.conflictRemoteUpdatedAt = nil
        entry.conflictRemoteEventDate = nil
    }
}

enum ConflictResolutionError: LocalizedError {
    case noConflict
    case missingRemoteData

    var errorDescription: String? {
        switch self {
        case .noConflict:
            return "このエントリーには競合がありません"
        case .missingRemoteData:
            return "リモートデータが不完全です"
        }
    }
}
