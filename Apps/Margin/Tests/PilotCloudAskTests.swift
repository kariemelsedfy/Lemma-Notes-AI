import InkCore
import Intelligence
import XCTest

@testable import Margin

@MainActor
final class PilotCloudAskTests: XCTestCase {
    private static let reply = Data(
        #"""
        {"version":1,"intent":"answer","read":"x + 2 =","readConfidence":0.9,
         "blocks":[{"type":"inline","placement":"atAnchor","content":{"kind":"math","latex":"84"}}]}
        """#.utf8)

    func testUrlValidationAcceptsOnlyAnHttpsOrigin() {
        XCTAssertNotNil(PilotCloudConfiguration.validatedURL(PilotCloudConfiguration.defaultServerText))
        XCTAssertNotNil(PilotCloudConfiguration.validatedURL(" https://pilot.example.test/ "))
        for bad in [
            "", "http://pilot.example.test", "https://", "pilot.example.test", "https://pilot.example.test/v1",
            "https://pilot.example.test?x=1", "https://user:pw@pilot.example.test", "https://pilot.example.test#f",
            "ftp://pilot.example.test",
        ] {
            XCTAssertNil(PilotCloudConfiguration.validatedURL(bad), bad)
        }
    }

    func testReadyNeedsEntitlementAndAValidAddress() {
        let (configuration, secrets) = makeConfiguration()
        XCTAssertFalse(configuration.isReady, "Free tier: no token, no cloud")
        configuration.setToken("  a-token  ")
        XCTAssertEqual(secrets.token(), "a-token")
        XCTAssertTrue(configuration.isEntitled)
        XCTAssertTrue(configuration.isReady)
        configuration.serverText = "http://insecure.example.test"
        XCTAssertFalse(configuration.isReady)
        configuration.serverText = PilotCloudConfiguration.defaultServerText
        configuration.setToken(nil)
        XCTAssertFalse(configuration.isReady)
    }

    func testTokenIsNeverStoredInUserDefaults() {
        let suite = "pilot-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = PilotCloudConfiguration(defaults: defaults, secrets: MemorySecrets())
        configuration.setToken("super-secret-token-value")
        let stored = defaults.dictionaryRepresentation().values.map { "\($0)" }.joined()
        XCTAssertFalse(stored.contains("super-secret-token-value"))
    }

    func testDefaultBuildStillAnswersArithmeticLocallyAndKeepsTheLocalFailureCopy() async throws {
        let transport = Recording(reply: Self.reply)
        let (configuration, _) = makeConfiguration()
        let answered = Harness(
            reading: SelectionReading(transcript: "2+3=", confidence: 0.95), configuration, transport)
        answered.pipeline.run(answered.input, verb: .answer)
        try await answered.settle()
        guard case .awaitingDecision = answered.model.state else { return XCTFail("Local arithmetic must answer") }

        let unsupported = Harness(
            reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, transport)
        unsupported.pipeline.run(unsupported.input, verb: .answer)
        try await unsupported.settle()
        XCTAssertEqual(unsupported.model.phase, .failed(.unreadable))
        XCTAssertTrue(unsupported.model.needsSubscription, "What local cannot answer is offered as Premium")
        let calls = await transport.requests.count
        XCTAssertEqual(calls, 0, "Nothing may leave the iPad without the premium entitlement")
    }

    func testTheFreeTierWithNoTokenNeverSendsAnything() async throws {
        let transport = Recording(reply: Self.reply)
        let (configuration, _) = makeConfiguration()
        let harness = Harness(reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, transport)
        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()
        let calls = await transport.requests.count
        XCTAssertEqual(calls, 0)
        XCTAssertTrue(harness.model.needsSubscription, "A free install is offered Premium, not an error")
    }

    func testAnEntitledBuildEscalatesOnlyWhatLocalCannotAnswer() async throws {
        let transport = Recording(reply: Self.reply)
        let (configuration, _) = makeConfiguration()
        configuration.setToken("tok")
        let harness = Harness(reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, transport)
        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()
        guard
            case .awaitingDecision(let spec, _) = harness.model.state,
            case .inline(let run) = try XCTUnwrap(spec.blocks.first).content
        else { return XCTFail("Expected the cloud answer as a suggestion") }
        XCTAssertEqual(run.value, "84")
        let sent = await transport.requests
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.transcript, "x+2=")
        XCTAssertEqual(sent.first?.maxOutputTokens, 512)
        XCTAssertTrue(harness.suggestions.strokes.isEmpty == false)
        XCTAssertEqual(harness.engine.strokes.count, 1, "Suggestion must not reach the page before Keep")
    }

    func testCloudFailureIsAnHonestTransportFailureWithNoInk() async throws {
        let transport = Recording(reply: nil, failure: .offline)
        let (configuration, _) = makeConfiguration()
        configuration.setToken("tok")
        let harness = Harness(reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, transport)
        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()
        XCTAssertEqual(harness.model.phase, .failed(.offline), "no network says so, not \"couldn't reach the model\"")
        // A content-free reason for debug builds: the failure case and the intent, nothing else.
        XCTAssertEqual(harness.model.failureDetail, "offline · answer")
        XCTAssertTrue(harness.suggestions.strokes.isEmpty)
    }

    func testASubscriberIsNeverToldToSubscribe() async throws {
        let transport = Recording(reply: Self.reply)
        let (configuration, _) = makeConfiguration()
        let harness = Harness(
            reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, transport, isPaid: true)
        harness.pipeline.run(harness.input, verb: .answer)
        try await harness.settle()
        XCTAssertFalse(harness.model.needsSubscription, "they already pay: this is a failure to retry")
        XCTAssertEqual(harness.model.phase, .failed(.transport))
    }

    func testASubscribersAskIsTriedOnceMoreWhenTheFirstReplyIsUnusable() async throws {
        let transport = Recording(reply: Self.reply, failuresFirst: 1)
        let (configuration, _) = makeConfiguration()
        configuration.setToken("tok")
        let paid = Harness(
            reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, transport, isPaid: true)
        paid.pipeline.run(paid.input, verb: .answer)
        try await paid.settle()
        guard case .awaitingDecision = paid.model.state else { return XCTFail("The second try should have answered") }
        let sent = await transport.requests.count
        XCTAssertEqual(sent, 2)

        let once = Recording(reply: Self.reply, failuresFirst: 1)
        let free = Harness(
            reading: SelectionReading(transcript: "x+2=", confidence: 0.95), configuration, once, isPaid: false)
        free.pipeline.run(free.input, verb: .answer)
        try await free.settle()
        XCTAssertEqual(free.model.phase, .failed(.transport))
        let freeSent = await once.requests.count
        XCTAssertEqual(freeSent, 1, "only a subscriber's ask is retried")
    }

    func testBundledTokenIsUsedOnlyWhenTheKeychainHasNone() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("PilotToken.local")
        let location: @Sendable () -> URL? = { FileManager.default.fileExists(atPath: file.path) ? file : nil }
        let empty = BundledFallbackSecretStore(primary: MemorySecrets(), location: location)
        XCTAssertNil(empty.token(), "no file, no token")

        try " bundled-token\n".write(
            to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(empty.token(), "bundled-token")

        let primary = MemorySecrets()
        primary.setToken("keychain-token")
        XCTAssertEqual(BundledFallbackSecretStore(primary: primary, location: location).token(), "keychain-token")
    }

    func testKeychainStoreRoundTripsReplacesAndRemovesTheToken() throws {
        let store = KeychainPilotSecretStore()
        let original = store.token()
        defer { store.setToken(original) }
        // Unsigned CI builds (CODE_SIGNING_ALLOWED=NO) have no Keychain entitlement; the signed device build
        // does. needs-device-verification.
        try XCTSkipUnless(store.setToken("probe-token"), "Keychain unavailable in this unsigned test host")
        XCTAssertTrue(store.setToken("first-token"))
        XCTAssertEqual(store.token(), "first-token")
        XCTAssertTrue(store.setToken(" second-token\n"))
        XCTAssertEqual(store.token(), "second-token")
        XCTAssertTrue(store.setToken(nil))
        XCTAssertNil(store.token())
        XCTAssertTrue(store.setToken("   "))
        XCTAssertNil(store.token())
    }

    // MARK: - helpers

    private func makeConfiguration() -> (PilotCloudConfiguration, MemorySecrets) {
        let suite = "pilot-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let secrets = MemorySecrets()
        return (PilotCloudConfiguration(defaults: defaults, secrets: secrets), secrets)
    }

    @MainActor private struct Harness {
        let model = AskBarModel()
        let suggestions = SuggestionLayer()
        let engine = PencilKitInkEngine()
        let pipeline: AskPipeline
        let input: AskPipeline.PageInput

        init(
            reading: SelectionReading, _ configuration: PilotCloudConfiguration, _ transport: Recording,
            isPaid: Bool = false
        ) {
            let ink = InkStroke(points: [
                InkPoint(location: CGPoint(x: 100, y: 100), timeOffset: 0, force: 0.5, altitude: 1, azimuth: 0),
                InkPoint(location: CGPoint(x: 320, y: 126), timeOffset: 1, force: 0.5, altitude: 1, azimuth: 0),
            ])
            engine.insertProgrammatic(strokes: [ink])
            input = AskPipeline.PageInput(
                engine: engine,
                loop: [
                    CGPoint(x: 80, y: 80), CGPoint(x: 340, y: 80),
                    CGPoint(x: 340, y: 150), CGPoint(x: 80, y: 150),
                ],
                pageSize: CGSize(width: 1_668, height: 2_388)
            )
            pipeline = AskPipeline(
                provider: VirtualizedPageStack.makeAskProvider(configuration: configuration, transport: transport),
                model: model,
                suggestions: suggestions,
                recognizeSelection: { _ in reading },
                isPaid: { isPaid }
            )
            model.selectionChanged(hasSelection: true)
        }

        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while model.phase == .working && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertNotEqual(model.phase, .working, "Ask must leave working state before assertions")
        }
    }
}

private final class MemorySecrets: PilotSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    func token() -> String? { lock.withLock { value } }

    func setToken(_ newValue: String?) -> Bool {
        lock.withLock { value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
        return true
    }
}

private actor Recording: ProxyClientTransport {
    private(set) var requests: [ProxyClientRequest] = []
    private let reply: Data?
    private let failure: ProxyTransportFailure?
    private let failuresFirst: Int

    init(reply: Data?, failure: ProxyTransportFailure? = nil, failuresFirst: Int = 0) {
        self.reply = reply
        self.failure = failure
        self.failuresFirst = failuresFirst
    }

    func response(to request: ProxyClientRequest) async throws -> Data {
        requests.append(request)
        if requests.count <= failuresFirst { throw ProxyTransportFailure.refused }
        if let failure { throw failure }
        return reply ?? Data()
    }
}
