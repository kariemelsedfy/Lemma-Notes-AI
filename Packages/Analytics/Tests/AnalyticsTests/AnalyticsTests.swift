import XCTest

@testable import Analytics

final class AnalyticsTests: XCTestCase {
    func testEventVocabularyCoversRequiredActions() {
        let events: [AnalyticsEvent] = [
            .appOpened,
            .noteCreated,
            .strokeSessionEnded(strokeCount: 4),
            .aiInvoked(intent: .answer, tier: .onDevice),
            .aiAccepted,
            .aiRejected,
            .paywallShown,
            .purchaseCompleted,
        ]

        XCTAssertEqual(events.count, 8)
    }

    func testTrackingOptOutBlocksTransport() async {
        let transport = RecordingTransport()
        let client = AnalyticsClient(transport: transport, isTrackingEnabled: false)

        await client.record(.appOpened)

        let events = await transport.events
        XCTAssertTrue(events.isEmpty)
    }

    func testEnabledTrackingForwardsTypedEvent() async {
        let transport = RecordingTransport()
        let client = AnalyticsClient(transport: transport)
        let event = AnalyticsEvent.aiInvoked(intent: .ask, tier: .privateCloudCompute)

        await client.record(event)

        let events = await transport.events
        XCTAssertEqual(events, [event])
    }
}

private actor RecordingTransport: AnalyticsTransport {
    private(set) var events: [AnalyticsEvent] = []

    func send(_ event: AnalyticsEvent) {
        events.append(event)
    }
}
