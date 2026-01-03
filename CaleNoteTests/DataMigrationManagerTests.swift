//
//  DataMigrationManagerTests.swift
//  CaleNoteTests
//
//  Created by Claude Code on 2025/01/03.
//

import XCTest
@testable import CaleNote
import SwiftData

/// SwiftData スキーママイグレーションのテスト
final class DataMigrationManagerTests: XCTestCase {
    // MARK: - Properties

    private var migrationManager: DataMigrationManager!
    private var container: ModelContainer!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        migrationManager = DataMigrationManager.shared
    }

    override func tearDown() async throws {
        container = nil
        try await super.tearDown()
    }

    // MARK: - Configuration Tests

    func testCreateInMemoryConfiguration() async throws {
        // インメモリ設定の作成
        let config = await migrationManager.createConfiguration(inMemory: true)

        XCTAssertTrue(config.isStoredInMemoryOnly, "In-memory configuration should be stored in memory only")
    }

    func testCreatePersistentConfiguration() async throws {
        // 永続化設定の作成
        let config = await migrationManager.createConfiguration(inMemory: false)

        XCTAssertFalse(config.isStoredInMemoryOnly, "Persistent configuration should not be in-memory")
    }

    // MARK: - ModelContainer Tests

    func testCreateModelContainerWithVersionedSchema() async throws {
        // VersionedSchema を使用した ModelContainer の作成
        let config = await migrationManager.createConfiguration(inMemory: true)

        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CaleNoteMigrationPlan.self,
            configurations: [config]
        )

        XCTAssertNotNil(container, "ModelContainer should be created successfully")
    }

    // MARK: - Schema Version Tests

    func testCurrentSchemaVersion() throws {
        // 現在のスキーマバージョンが正しいことを確認
        XCTAssertEqual(CurrentSchema.versionIdentifier.major, 1)
        XCTAssertEqual(CurrentSchema.versionIdentifier.minor, 0)
        XCTAssertEqual(CurrentSchema.versionIdentifier.patch, 0)
    }

    func testCurrentSchemaModels() throws {
        // 現在のスキーマに必要なモデルが含まれていることを確認
        let models = CurrentSchema.models

        XCTAssertTrue(models.contains(where: { $0 == ScheduleEntry.self }), "Schema should include ScheduleEntry")
        XCTAssertTrue(models.contains(where: { $0 == CalendarInfo.self }), "Schema should include CalendarInfo")
        XCTAssertTrue(models.contains(where: { $0 == SyncLog.self }), "Schema should include SyncLog")
    }

    // MARK: - MigrationPlan Tests

    func testMigrationPlanSchemas() throws {
        // MigrationPlan に V1 が含まれていることを確認
        let schemas = CaleNoteMigrationPlan.schemas

        XCTAssertEqual(schemas.count, 1, "MigrationPlan should have one schema")
        XCTAssertTrue(schemas.contains(where: { $0 == CaleNoteSchemaV1.self }), "MigrationPlan should include V1")
    }

    func testMigrationPlanStages() throws {
        // 現時点ではマイグレーションステージはない（V1のみ）
        let stages = CaleNoteMigrationPlan.stages

        XCTAssertEqual(stages.count, 0, "MigrationPlan should have no stages for V1")
    }

    // MARK: - Backup Tests

    func testBackupDirectoryCreation() async throws {
        // バックアップディレクトリの作成をテスト
        let config = await migrationManager.createConfiguration(inMemory: true)
        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: [config]
        )
        let context = await container.mainContext

        // バックアップの作成を試みる（インメモリなのでファイルは作成されない）
        let backupURL = try await migrationManager.createBackup(using: context)
        // インメモリモードではバックアップは作成されない
        XCTAssertNil(backupURL, "In-memory stores should not create backups")
    }

    // MARK: - Integration Tests

    func testModelContainerInitialization() async throws {
        // ModelContainer の初期化統合テスト
        let config = await migrationManager.createConfiguration(inMemory: true)

        let schema = Schema(CurrentSchema.models)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CaleNoteMigrationPlan.self,
            configurations: [config]
        )

        let context = await container.mainContext

        // ScheduleEntry の作成ができることを確認
        let entry = ScheduleEntry(
            source: "calenote",
            managedByCaleNote: true,
            googleEventId: "test-event-id",
            calendarId: "primary",
            startAt: Date(),
            endAt: Date().addingTimeInterval(3600),
            isAllDay: false,
            title: "Test Entry",
            body: nil,
            tags: [],
            syncStatus: ScheduleEntry.SyncStatus.synced.rawValue,
            lastSyncedAt: nil,
            isDeleted: false,
            deletedAt: nil
        )

        context.insert(entry)

        // データが保存されたことを確認
        let fetchDescriptor = FetchDescriptor<ScheduleEntry>()
        let entries = try context.fetch(fetchDescriptor)

        XCTAssertEqual(entries.count, 1, "Should have one entry")
        XCTAssertEqual(entries.first?.title, "Test Entry")
    }
}
