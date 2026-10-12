import AWSBedrockRuntime
import Foundation

enum SDKTransportError: Error, Equatable {
    case disabled
}

struct DisabledBedrockTransport: ProxyTransport {
    func send(_ request: AdmittedRequest) async throws {
        throw SDKTransportError.disabled
    }
}

enum SyntheticNovaProbe {
    static func request() -> ConverseInput {
        let message = BedrockRuntimeClientTypes.Message(content: [.text("2+3=")], role: .user)
        return ConverseInput(
            inferenceConfig: BedrockRuntimeClientTypes.InferenceConfiguration(maxTokens: 32),
            messages: [message], modelId: "amazon.nova-lite-v1:0"
        )
    }
}
