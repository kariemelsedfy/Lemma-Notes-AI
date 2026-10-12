import Darwin
import Foundation
import ProxyAdmission

@main
struct PricingObserve {
    static func main() async {
        guard let account = ProcessInfo.processInfo.environment["MARGIN_PILOT_ACCOUNT_ID"],
            let rates = await PilotPricingObservation.observe(expectedAccount: account)
        else {
            FileHandle.standardError.write(Data("Limited pilot identity or public token prices unavailable.\n".utf8))
            exit(1)
        }
        let fetchedAt = ISO8601DateFormatter().string(from: rates.fetchedAt)
        print("\(rates.modelLabel) us-east-1 catalog tokens at \(fetchedAt):")
        print("input: \(rates.inputMicrosPerMillion) micro-USD/million tokens")
        print("output: \(rates.outputMicrosPerMillion) micro-USD/million tokens")
        print("No Runtime model binding or image/other-charge maximum; paid admission remains disabled.")
    }
}
