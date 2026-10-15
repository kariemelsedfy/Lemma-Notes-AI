import Foundation
import ProxyAdmission

do {
    try await PilotServer.run()
} catch {
    PilotServer.log("pilot-proxy: could not start (\(error))")
    exit(1)
}
