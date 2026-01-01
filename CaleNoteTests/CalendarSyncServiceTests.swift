import Foundation
import SwiftData
import Testing
@testable import CaleNote

@MainActor
struct CalendarSyncServiceTests {
    final class MockGoogleCalendarClient: GoogleCalendarClientProtocol {
        struct CreateCall {
            let calendarId: String
            let event: CalendarEvent
        }

        struct UpdateCall {
            let calendarId: String
            let eventId: String
            let event: CalendarEvent
        }

        var createdEvents: [CreateCall] = []
        var updatedEvents: [UpdateCall] = []
        var deletedEvents: [(String, String)] = []
        var createEventResult = CalendarEvent(
            id: "mock-created",
            status: nil,
            summary: nil,
            description: nil,
            start: nil,
            end: nil,
            created: nil,
            updated: nil,
            etag: nil,
            extendedProperties: nil,
            recurrence: nil,
            recurringEventId: nil,
            originalStartTime: nil
        )
        var updateEventResult = CalendarEvent(
            id: "mock-updated",
            status: nil,
            summary: nil,
            description: nil,
            start: nil,
            end: nil,
            created: nil,
            updated: nil,
            etag: nil,
            extendedProperties: nil,
            recurrence: nil,
            recurringEventId: nil,
            originalStartTime: nil
        )
        var createEventError: Error?
        var updateEventError: Error?

        func getCalendarList(pageToken: String?, syncToken: String?) async throws -> CalendarList {
            CalendarList(kind: nil, etag: nil, nextPageToken: nil, nextSyncToken: nil, items: [])
        }

        func createEvent(calendarId: String, event: CalendarEvent) async throws -> CalendarEvent {
            createdEvents.append(.init(calendarId: calendarId, event: event))
            if let createEventError {
                throw createEventError
            }
            return createEventResult
        }

        func updateEvent(calendarId: String, eventId: String, event: CalendarEvent) async throws -> CalendarEvent {
            updatedEvents.append(.init(calendarId: calendarId, eventId: eventId, event: event))
            if let updateEventError {
                throw updateEventError
            }
            return updateEventResult
        }

        func deleteEvent(calendarId: String, eventId: String) async throws {
            deletedEvents.append((calendarId, eventId))
        }

        func listEvents(
            calendarId: String,
            timeMin: String?,
            timeMax: String?,
            pageToken: String?,
            syncToken: String?,
            maxResults: Int
        ) async throws -> EventListResponse {
            EventListResponse(
                kind: nil,
                etag: nil,
                summary: nil,
                updated: nil,
                timeZone: nil,
                accessRole: nil,
                nextPageToken: nil,
                nextSyncToken: nil,
                items: []
            )
        }

        func listEventsSince(calendarId: String, syncToken: String) async throws -> EventListResponse {
            EventListResponse(
                kind: nil,
                etag: nil,
                summary: nil,
                updated: nil,
                timeZone: nil,
                accessRole: nil,
                nextPageToken: nil,
                nextSyncToken: nil,
                items: []
            )
        }
    }

    @Test func syncLocalChangesCreatesNewEvent() async throws {
        let context = TestHelpers.makeModelContext()
        let entry = TestHelpers.makeEntry(
            title: "New Entry",
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 10),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 10, hour: 11)
        )
        context.insert(entry)
        try context.save()

        let apiClient = MockGoogleCalendarClient()
        apiClient.createEventResult = CalendarEvent(
            id: "event-1",
            status: nil,
            summary: nil,
            description: nil,
            start: nil,
            end: nil,
            created: nil,
            updated: nil,
            etag: nil,
            extendedProperties: nil,
            recurrence: nil,
            recurringEventId: nil,
            originalStartTime: nil
        )

        let originalCalendarId = CalendarSettings.shared.targetCalendarId
        CalendarSettings.shared.targetCalendarId = "test-calendar"
        defer { CalendarSettings.shared.targetCalendarId = originalCalendarId }

        let service = CalendarSyncService(
            apiClient: apiClient,
            authService: .shared,
            searchIndexService: SearchIndexService(),
            relatedIndexService: RelatedEntriesIndexService(),
            errorHandler: .shared,
            modelContext: context,
            calendarSettings: .shared,
            rateLimiter: SyncRateLimiter(minInterval: 0)
        )

        try await service.syncLocalChangesToGoogle()

        #expect(apiClient.createdEvents.count == 1)
        #expect(apiClient.createdEvents.first?.calendarId == "test-calendar")
        #expect(entry.googleEventId == "event-1")
        #expect(entry.isSynced)
        #expect(service.pendingSyncCount == 0)
    }

    @Test func syncLocalChangesUpdatesExistingEvent() async throws {
        let context = TestHelpers.makeModelContext()
        let entry = TestHelpers.makeEntry(
            title: "Existing Entry",
            startAt: TestHelpers.makeDate(year: 2025, month: 1, day: 12),
            endAt: TestHelpers.makeDate(year: 2025, month: 1, day: 12, hour: 13),
            googleEventId: "event-xyz"
        )
        context.insert(entry)
        try context.save()

        let apiClient = MockGoogleCalendarClient()
        apiClient.updateEventResult = CalendarEvent(
            id: "event-xyz",
            status: nil,
            summary: nil,
            description: nil,
            start: nil,
            end: nil,
            created: nil,
            updated: nil,
            etag: nil,
            extendedProperties: nil,
            recurrence: nil,
            recurringEventId: nil,
            originalStartTime: nil
        )

        let service = CalendarSyncService(
            apiClient: apiClient,
            authService: .shared,
            searchIndexService: SearchIndexService(),
            relatedIndexService: RelatedEntriesIndexService(),
            errorHandler: .shared,
            modelContext: context,
            calendarSettings: .shared,
            rateLimiter: SyncRateLimiter(minInterval: 0)
        )

        try await service.syncLocalChangesToGoogle()

        #expect(apiClient.updatedEvents.count == 1)
        #expect(apiClient.updatedEvents.first?.eventId == "event-xyz")
        #expect(entry.googleEventId == "event-xyz")
        #expect(entry.isSynced)
    }
}
