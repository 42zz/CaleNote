//
//  DataRecoveryService.swift
//  CaleNote
//
//  Created by Claude Code on 2025/12/30.
//

import Combine
import Foundation
import OSLog
import SwiftData

/// ローカルデータの復旧と再構築を行うサービス
@MainActor
final class DataRecoveryService: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isRecovering = false
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var lastError: CaleNoteError?

    // MARK: - Logger

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CaleNote", category: "DataRecovery")

    // MARK: - Integrity Check

    /// データ整合性チェック（簡易）
    func checkIntegrity(modelContext: ModelContext) -> Bool {
        do {
            let descriptor = FetchDescriptor<ScheduleEntry>()
            _ = try modelContext.fetch(descriptor)
            return true
        } catch {
            logger.error("Integrity check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Clear Local Data

    /// ローカルデータを削除
    func clearLocalData(modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<ScheduleEntry>()
        let entries = try modelContext.fetch(descriptor)
        for entry in entries {
            modelContext.delete(entry)
        }
        try modelContext.save()
        logger.info("Cleared \(entries.count) local entries")
    }

    // MARK: - Recovery

    /// Google Calendar からローカルデータを再構築
    func recoverFromGoogle(
        modelContext: ModelContext,
        syncService: CalendarSyncService,
        pastDays: Int,
        futureDays: Int
    ) async {
        if isRecovering { return }
        isRecovering = true
        progress = 0.0
        statusMessage = L10n.tr("recovery.starting")
        lastError = nil

        do {
            statusMessage = L10n.tr("recovery.clearing_local")
            try clearLocalData(modelContext: modelContext)
            progress = 0.3

            // syncToken をクリアして完全同期
            syncService.resetSyncTokens()

            statusMessage = L10n.tr("recovery.fetching_google")
            try await syncService.syncGoogleChangesToLocal(
                pastDays: pastDays,
                futureDays: futureDays
            )
            progress = 0.85

            statusMessage = L10n.tr("recovery.rebuilding_index")
            // NOTE: Index services are not implemented yet.
            progress = 1.0

            statusMessage = L10n.tr("recovery.completed")
            logger.info("Data recovery completed")
        } catch let error as CaleNoteError {
            lastError = error
            statusMessage = L10n.tr("recovery.failed")
            logger.error("Data recovery failed: \(error.localizedDescription)")
        } catch {
            let wrapped = CaleNoteError.unknown(error)
            lastError = wrapped
            statusMessage = L10n.tr("recovery.failed")
            logger.error("Data recovery failed: \(error.localizedDescription)")
        }

        isRecovering = false
    }
}
