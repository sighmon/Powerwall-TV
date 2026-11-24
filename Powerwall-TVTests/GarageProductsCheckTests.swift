import Foundation
import Testing
@testable import Powerwall_TV

/// Synthetic `/api/1/products` replies. VINs follow the demo pattern; no real account data.
private final class ProductsProtocol: URLProtocol, @unchecked Sendable {
    @MainActor static var paths: [String] = []
    @MainActor static var status = 200
    @MainActor static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Task { @MainActor in
            Self.paths.append(request.url!.path)
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

private let syntheticProducts = Data("""
{"response":[
  {"energy_site_id":1000000001,"resource_type":"battery","site_name":"Test Home","id":"STE-TEST-0001"},
  {"id":100000000000001,"vehicle_id":2000001,"vin":"5YJYGDEE5LF000001","display_name":"Test Car","state":"asleep","color":null},
  {"device_type":"vehicle","vin":"5YJ3GDEE5RF000001","display_name":null,"state":"online"},
  {"vin":"5yjygdee5lf000001","display_name":"Same car again"},
  {"device_type":"energy","vin":"TESTVIN0000000009","energy_site_id":1000000002}
],"count":5}
""".utf8)

@MainActor
@Suite(.serialized)
struct GarageProductsCheckTests {
    private func model(status: Int = 200, body: Data = syntheticProducts) -> PowerwallViewModel {
        ProductsProtocol.paths = []
        ProductsProtocol.status = status
        ProductsProtocol.body = body
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProductsProtocol.self]
        let model = PowerwallViewModel(fleetURLSession: URLSession(configuration: configuration))
        model.ipAddress = "gateway.example"
        model.loginMode = .fleetAPI
        model.accessToken = "test-only"
        model.vehicles = []
        return model
    }

    private func check(_ model: PowerwallViewModel, now: Date = Date()) async {
        await withCheckedContinuation { continuation in
            model.checkConnectedVehicles(now: now) { continuation.resume() }
        }
    }

    @Test func productsListsTheAccountsCarsAndSkipsEnergySites() throws {
        let vehicles = try ProductsResponse.vehicles(from: syntheticProducts)
        #expect(vehicles.map(\.vin) == ["5YJYGDEE5LF000001", "5YJ3GDEE5RF000001"])
        #expect(vehicles.first?.displayName == "Test Car")
        #expect(vehicles.first?.state == "asleep")
        let sitesOnly = Data(#"{"response":[{"energy_site_id":1000000001}]}"#.utf8)
        #expect(try ProductsResponse.vehicles(from: sitesOnly).isEmpty)
        #expect(throws: (any Error).self) { try ProductsResponse.vehicles(from: Data("{}".utf8)) }
    }

    @Test func checkPolicySkipsDemoLocalAndFreshAnswers() {
        let now = Date()
        #expect(ConnectedVehicleCheck.shouldFetch(isDemoMode: false, isFleetLogin: true, hasToken: true, checkedAt: nil, now: now))
        #expect(!ConnectedVehicleCheck.shouldFetch(isDemoMode: true, isFleetLogin: true, hasToken: true, checkedAt: nil, now: now))
        #expect(!ConnectedVehicleCheck.shouldFetch(isDemoMode: false, isFleetLogin: false, hasToken: true, checkedAt: nil, now: now))
        #expect(!ConnectedVehicleCheck.shouldFetch(isDemoMode: false, isFleetLogin: true, hasToken: false, checkedAt: nil, now: now))
        let fresh = now.addingTimeInterval(-60)
        let stale = now.addingTimeInterval(-ConnectedVehicleCheck.maxAge)
        #expect(!ConnectedVehicleCheck.shouldFetch(isDemoMode: false, isFleetLogin: true, hasToken: true, checkedAt: fresh, now: now))
        #expect(ConnectedVehicleCheck.shouldFetch(isDemoMode: false, isFleetLogin: true, hasToken: true, checkedAt: stale, now: now))
        #expect(ConnectedVehicleCheck.timeout <= 5)
    }

    @Test func garageTapAsksProductsOnceAndReusesTheAnswer() async {
        let model = model()
        let now = Date()
        var finished = 0
        await withCheckedContinuation { continuation in
            for _ in 0..<3 {
                model.checkConnectedVehicles(now: now) {
                    finished += 1
                    if finished == 3 { continuation.resume() }
                }
            }
        }
        #expect(ProductsProtocol.paths == ["/api/1/products"])
        #expect(model.vehicles.map(\.vin) == ["5YJYGDEE5LF000001", "5YJ3GDEE5RF000001"])

        await check(model, now: now.addingTimeInterval(60))
        #expect(ProductsProtocol.paths.count == 1)
        await check(model, now: now.addingTimeInterval(ConnectedVehicleCheck.maxAge + 1))
        #expect(ProductsProtocol.paths.count == 2)
        #expect(model.vehicles.count == 2)
    }

    @Test(arguments: [500, 403])
    func failedProductsKeepsWhatIsKnownAndTriesAgainNextTap(_ status: Int) async {
        let model = model(status: status, body: Data(#"{"error":"test"}"#.utf8))
        await check(model)
        #expect(model.vehicles.isEmpty)
        #expect(model.errorMessage == nil)
        await check(model)
        #expect(ProductsProtocol.paths.count == 2)
    }

    @Test func demoAndLocalLoginsOpenAtOnceWithoutCallingFleet() {
        let setups: [(PowerwallViewModel) -> Void] = [
            { $0.ipAddress = "demo" },
            { $0.loginMode = .local },
            { $0.accessToken = "" },
        ]
        for setup in setups {
            let model = model()
            setup(model)
            var completed = false
            model.checkConnectedVehicles { completed = true }
            #expect(completed)
            #expect(ProductsProtocol.paths.isEmpty)
        }
    }
}
