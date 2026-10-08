import Foundation
import Testing
@testable import Powerwall_TV

private final class GatewayProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var beforeLoginReply: (() -> Void)?
    @MainActor static var paths: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            let path = request.url!.path
            Self.paths.append(path)
            var headers: [String: String] = [:]
            if path == "/api/login/Basic" {
                Self.beforeLoginReply?()
                headers["Set-Cookie"] = "AuthCookie=test-only; Path=/; Secure"
            }
            let valid = request.httpMethod == "POST" && ["/api/login/Basic", "/api/v2/islanding/mode"].contains(path)
            let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 400, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

@MainActor
@Suite(.serialized)
struct GatewayAuthenticationTests {
    private func model() -> PowerwallViewModel {
        GatewayProtocol.paths = []
        GatewayProtocol.beforeLoginReply = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatewayProtocol.self]
        let model = PowerwallViewModel(localURLSession: URLSession(configuration: configuration))
        model.loginMode = .fleetAPI
        model.ipAddress = "gateway.example"
        model.password = "test-only"
        return model
    }

    private func execute(_ mode: PowerwallOperationMode, using model: PowerwallViewModel) async -> Result<Void, Error> {
        await withCheckedContinuation { continuation in
            model.setPowerwallOperationMode(mode, retryCount: 0) { continuation.resume(returning: $0) }
        }
    }

    @Test(arguments: [PowerwallOperationMode.offGrid, .onGrid])
    func fleetModeCanAuthenticateAndSendIslandCommands(_ mode: PowerwallOperationMode) async throws {
        let model = model()
        let result = await execute(mode, using: model)
        try result.get()
        #expect(GatewayProtocol.paths == ["/api/login/Basic", "/api/v2/islanding/mode"])
    }

    @Test(arguments: ["demo", "gateway-changed.example", "mode-changed"])
    func changedConnectionRejectsPendingAuthentication(_ change: String) async {
        let model = model()
        GatewayProtocol.beforeLoginReply = {
            if change == "mode-changed" { model.loginMode = .local }
            else { model.ipAddress = change }
        }
        defer { GatewayProtocol.beforeLoginReply = nil }
        let result = await execute(.offGrid, using: model)
        if case .success = result { Issue.record("A stale login must not send an island command") }
        #expect(GatewayProtocol.paths == ["/api/login/Basic"])
        #expect(model.errorMessage == nil)
    }

    @Test func demoDoesNotStartGatewayAuthentication() async {
        let model = model()
        model.ipAddress = "demo"
        let result = await execute(.offGrid, using: model)
        if case .success = result { Issue.record("Demo must not send an island command") }
        #expect(GatewayProtocol.paths.isEmpty)
    }
}
