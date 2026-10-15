import Foundation
import XCTest

@testable import ProxyAdmission

final class SDKSeamTests: XCTestCase {
    func testSyntheticRequestIsBoundedToTheExactNovaLiteModel() {
        let input = SyntheticNovaProbe.request()
        XCTAssertEqual(input.modelId, "amazon.nova-lite-v1:0")
        XCTAssertEqual(input.inferenceConfig?.maxTokens, 32)
    }

    func testSDKTransportRefusesEvenAWellFormedRequestWithoutAClient() async throws {
        let pngBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/" + "x8AAusB9o8cRcwAAAAASUVORK5CYII="
        let pixel = try XCTUnwrap(Data(base64Encoded: pngBase64))
        let body: [String: Any] = [
            "requestID": UUID().uuidString,
            "cropPNG": pixel.base64EncodedString(),
            "neighborhoodPNG": pixel.base64EncodedString(),
            "transcript": "2+3=", "intent": "answer", "maxOutputTokens": 32,
        ]
        let request = try JSONDecoder().decode(
            AdmittedRequest.self, from: JSONSerialization.data(withJSONObject: body)
        )
        do {
            try await DisabledBedrockTransport().send(request)
            XCTFail("No-call SDK boundary allowed a transport send")
        } catch let error as SDKTransportError {
            XCTAssertEqual(error, .disabled)
        }
    }
}
