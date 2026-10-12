import Darwin
import Foundation
import ProxyAdmission

@main
struct BedrockObserve {
    static func main() async {
        guard let account = ProcessInfo.processInfo.environment["MARGIN_PILOT_ACCOUNT_ID"],
            let observation = await PilotBedrockObservation.observe(expectedAccount: account)
        else {
            FileHandle.standardError.write(Data("Limited pilot identity or Bedrock metadata unavailable.\n".utf8))
            exit(1)
        }
        let checkedAt = ISO8601DateFormatter().string(from: observation.checkedAt)
        print("Requested \(observation.requestedModelID), reported \(observation.reportedModelID)")
        print("Region: \(observation.requestedRegion) at \(checkedAt)")
        print("Account retention: \(observation.accountMode)")
        print("Account mode and model availability do not prove model-specific eligibility or authorize a call.")
    }
}
