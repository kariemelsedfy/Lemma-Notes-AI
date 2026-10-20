import Foundation

/// The attested-install side of the proxy (ADR-031): hands out challenges, registers installs, accepts their signed
/// App Store transactions, and runs their hosted asks under the server-enforced allowances. Every reply is
/// content-free: a status and, on success, a few fields about the caller's own install.
struct InstallGate: Sendable {
    static let challengePath = "/v1/challenge"
    static let registerPath = "/v1/register"
    static let entitlementPath = "/v1/entitlement"
    static let keyHeader = "x-install-key"
    static let assertionHeader = "x-install-assertion"

    let trust: InstallTrust
    /// Nil leaves purchases unverifiable, so every install stays on the free plan.
    let transactions: AppleTransactionVerifier?
    let now: @Sendable () -> Date

    struct Credentials: Sendable {
        let keyID: Data
        let assertion: Data
    }

    func credentials(in headers: [String: String]) -> Credentials? {
        guard let key = headers[Self.keyHeader].flatMap({ Data(base64Encoded: $0) }), key.count == 32,
            let assertion = headers[Self.assertionHeader].flatMap({ Data(base64Encoded: $0) }), !assertion.isEmpty
        else { return nil }
        return Credentials(keyID: key, assertion: assertion)
    }

    // MARK: - Routes

    func challenge() -> HTTPReply {
        json(200, ["challenge": trust.newChallenge().base64EncodedString()])
    }

    func register(body: Data) async -> HTTPReply {
        guard let fields = try? JSONSerialization.jsonObject(with: body) as? [String: String],
            let keyID = fields["keyID"].flatMap({ Data(base64Encoded: $0) }),
            let attestation = fields["attestation"].flatMap({ Data(base64Encoded: $0) }),
            let challenge = fields["challenge"].flatMap({ Data(base64Encoded: $0) })
        else { return HTTPReply(status: 400) }
        do {
            try await trust.register(attestation: attestation, challenge: challenge, keyID: keyID)
            return json(200, [:])
        } catch InstallTrustError.invalidChallenge {
            return HTTPReply(status: 400)
        } catch InstallTrustError.alreadyRegistered {
            return HTTPReply(status: 409)
        } catch is AppAttestError {
            return HTTPReply(status: 401)
        } catch {
            return HTTPReply(status: 422)
        }
    }

    /// The caller proves it is the install (assertion over the body), then its signed transaction is verified and
    /// folded into the record.
    func entitlement(headers: [String: String], body: Data) async -> HTTPReply {
        guard let credentials = credentials(in: headers) else { return HTTPReply(status: 401) }
        guard let fields = try? JSONSerialization.jsonObject(with: body) as? [String: String],
            let signed = fields["transaction"]
        else { return HTTPReply(status: 400) }
        do {
            try await trust.authorize(keyID: credentials.keyID, assertion: credentials.assertion, clientData: body)
            guard let verifier = transactions, let transaction = try? await verifier.verify(signed) else {
                return HTTPReply(status: 422)
            }
            let moment = now()
            let record = try await trust.update(keyID: credentials.keyID) { $0.apply(transaction, at: moment) }
            return json(200, ["plan": record.effectivePlan(at: moment).rawValue])
        } catch {
            return HTTPReply(
                status: PilotRouter.reply(for: PilotOutcome(status: PilotService.status(for: error), body: Data()))
                    .status)
        }
    }

    private func json(_ status: Int, _ object: [String: String]) -> HTTPReply {
        HTTPReply(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
    }
}

extension PilotService {
    /// One hosted ask from an attested install. The assertion and the allowance hold are written together, so a
    /// refused request never advances the counter; after the call the hold is replaced by the real cost, or given
    /// back if the ask was not served.
    func handle(body: Data, install credentials: InstallGate.Credentials, gate: InstallGate) async -> PilotOutcome {
        let hold = (try? PilotPriceEnvelope.quote(maxOutputTokens: 512).reservationMicros) ?? 50_000
        let moment = gate.now()
        do {
            try await gate.trust.authorize(
                keyID: credentials.keyID, assertion: credentials.assertion, clientData: body
            ) { try InstallAllowance.reserve(&$0, micros: hold, at: moment) }
        } catch {
            return PilotOutcome(status: Self.status(for: error), body: Data())
        }
        let identity = PilotIdentity(subjectID: Self.subject(for: credentials.keyID))
        do {
            let answer = try await pilot.invoke(body, identity: identity, transport: transport)
            _ = try? await gate.trust.update(keyID: credentials.keyID) {
                InstallAllowance.settle(&$0, reserved: hold, observed: answer.observedMicros, at: moment)
            }
            return PilotOutcome(status: .success, body: answer.specJSON)
        } catch {
            _ = try? await gate.trust.update(keyID: credentials.keyID) {
                InstallAllowance.refund(&$0, reserved: hold, at: moment)
            }
            return Self.refused(error)
        }
    }

    /// A stable UUID for the ledger's per-pilot rate window, from the first 16 bytes of the key id.
    static func subject(for keyID: Data) -> String {
        let bytes = Array(keyID.prefix(16))
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            )
        ).uuidString
    }
}
