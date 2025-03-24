//
//  PowerwallViewModel.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//


import Foundation
import Combine
import AuthenticationServices // For ASWebAuthenticationSession

// Enum to define login options
enum LoginMode: String, CaseIterable {
    case local = "local"
    case fleetAPI = "fleetAPI"
}

class PowerwallViewModel: ObservableObject {
    // Published properties for UI binding

    // Local login
    @Published var loginMode: LoginMode = LoginMode(rawValue: UserDefaults.standard.string(forKey: "loginMode") ?? "local") ?? .local
    @Published var ipAddress: String = UserDefaults.standard.string(forKey: "gatewayIP") ?? ""
    @Published var username: String = UserDefaults.standard.string(forKey: "username") ?? "customer"
    @Published var password: String = KeychainWrapper.standard.string(forKey: "gatewayPassword") ?? ""

    @Published var data: PowerwallData?
    @Published var batteryPercentage: BatteryPercentage?
    @Published var gridStatus: GridStatus?
    @Published var errorMessage: String?

    // Tesla Fleet API credentials (replace with your actual values)
    private let clientID = Secrets.clientID
    private let clientSecret = Secrets.clientSecret
    private let redirectURI = "powerwalltv://app/callback" // Must match Tesla's registered URI
    private let scopes = "openid energy_device_data" // Adjust based on needs

    // Fleet API-specific properties
    @Published var accessToken: String = KeychainWrapper.standard.string(forKey: "fleetAPI_accessToken") ?? ""
    @Published var energySiteId: String?

    private var cancellables = Set<AnyCancellable>()

    // URLSession instances
    private let localURLSession: URLSession  // For local, insecure connections
    private let fleetURLSession = URLSession.shared  // For Fleet API

    init() {
        let delegate = InsecureURLSessionDelegate() // Custom delegate for local SSL bypass
        self.localURLSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Login Methods

    // Logs in based on the selected login mode
    func login(completion: @escaping (Bool) -> Void) {
        switch loginMode {
        case .local:
            if ipAddress.isEmpty || password.isEmpty {
                errorMessage = "Missing IP address or password for local login"
                completion(false)
                return
            }
            localLogin(ipAddress: ipAddress, password: password, completion: completion)
        case .fleetAPI:
            loginWithTeslaFleetAPI()
            completion(true) // Asynchronous; handle completion in callback
        }
    }

    // MARK: - Local Login

    private func localLogin(ipAddress: String, password: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://\(ipAddress)/api/login/Basic") else {
            errorMessage = "Invalid login URL"
            completion(false)
            return
        }

        let loginPayload: [String: Any] = [
            "username": "customer",
            "password": password,
            "email": username,
            "force_sm_off": false
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: loginPayload) else {
            errorMessage = "Failed to serialize login payload"
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        localURLSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Login failed: \(error.localizedDescription)"
                    completion(false)
                }
                return
            }

            if let httpResponse = response as? HTTPURLResponse,
               HTTPCookie.cookies(withResponseHeaderFields: httpResponse.allHeaderFields as? [String: String] ?? [:], for: url).contains(where: { $0.name == "AuthCookie" }) {
                DispatchQueue.main.async {
                    completion(true) // Success
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Login failed: No AuthCookie received"
                    completion(false)
                }
            }
        }.resume()
    }

    // MARK: - Tesla Fleet API Login

    private func loginWithTeslaFleetAPI() {
        let state = UUID().uuidString
        let authURLString = "https://auth.tesla.com/oauth2/v3/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scopes)&state=\(state)"

        guard let authURL = URL(string: authURLString) else {
            errorMessage = "Invalid authorization URL"
            return
        }

        let authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "powerwalltv") { [weak self] callbackURL, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Login failed: \(error.localizedDescription)"
                }
                return
            }

            guard let callbackURL = callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to retrieve authorization code"
                }
                return
            }

            self.exchangeCodeForToken(code: code)
        }

        authSession.start()
    }

    private func exchangeCodeForToken(code: String) {
        guard let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token") else {
            errorMessage = "Invalid token URL"
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=authorization_code&client_id=\(clientID)&client_secret=\(clientSecret)&code=\(code)&redirect_uri=\(redirectURI)"
        request.httpBody = body.data(using: .utf8)

        fleetURLSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Token exchange failed: \(error.localizedDescription)"
                }
                return
            }

            guard let data = data,
                  let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to decode token response"
                }
                return
            }

            DispatchQueue.main.async {
                self.accessToken = tokenResponse.access_token
                // Save the accessToken to Keychain
                KeychainWrapper.standard.set(tokenResponse.access_token, forKey: "fleetAPI_accessToken")
                self.fetchEnergyProducts()
            }
        }.resume()
    }

    private func fetchEnergyProducts() {
        if accessToken == "" {
            errorMessage = "No access token available"
            return
        }

        guard let url = URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/products") else {
            errorMessage = "Invalid products URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        fleetURLSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: ProductsResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = "Failed to fetch products: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] productsResponse in
                let energyProducts = productsResponse.response.filter { $0.deviceType == "energy" }
                if let firstEnergyProduct = energyProducts.first, let id = firstEnergyProduct.energySiteId {
                    self?.energySiteId = String(id) // Use energy_site_id as the device ID
                    self?.fetchFleetAPIData()
                } else {
                    self?.errorMessage = "No energy products found"
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Fetching

    func fetchData() {
        switch loginMode {
        case .local:
            // Ensure login before fetching data
            login { success in
                if success {
                    self.fetchLocalDataAfterLogin()
                    self.fetchLocalBatteryPercentage()
                    self.fetchLocalGridStatus()
                }
                // If login fails, errorMessage is already set by the login function
            }
        case .fleetAPI:
            if accessToken != "" {
                // TODO: how do we check for expired accessToken?
                // Token exists, try fetching devices or data directly
                self.fetchEnergyProducts()
            } else {
                // No token, initiate login
                login { success in
                    if success {
                        self.fetchEnergyProducts()
                    }
                    // If login fails, errorMessage is already set by the login function
                }
            }
        }
    }

    private func fetchLocalDataAfterLogin() {
        if ipAddress.isEmpty {
            errorMessage = "Missing IP address"
        }
        guard let url = URL(string: "https://\(ipAddress)/api/meters/aggregates") else {
            errorMessage = "Invalid data URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        localURLSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: PowerwallData.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = "Failed to fetch local data: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] data in
                self?.data = data
            }
            .store(in: &cancellables)
    }

    // Fetches battery percentage from the /api/system_status/soe endpoint
    private func fetchLocalBatteryPercentage() {
        guard let url = URL(string: "https://\(ipAddress)/api/system_status/soe") else {
            self.errorMessage = "Invalid battery percentage URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        localURLSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: BatteryPercentage.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = "Failed to fetch battery percentage: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] percentage in
                self?.batteryPercentage = percentage
            }
            .store(in: &cancellables)
    }

    // Fetches the grid connection status from the /api/system_status/grid_status endpoint
    private func fetchLocalGridStatus() {
        guard let url = URL(string: "https://\(ipAddress)/api/system_status/grid_status") else {
            self.errorMessage = "Invalid grid status URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        localURLSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: GridStatus.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = "Failed to fetch grid status: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] status in
                self?.gridStatus = status
            }
            .store(in: &cancellables)
    }

    func isOffGrid() -> Bool {
        return gridStatus?.status ?? "" == "SystemIslandedActive" || gridStatus?.status ?? "" == "Inactive"
    }

    func batteryCountString() -> String {
        guard let batteryCount: Double = data?.battery.count else {
            return ""
        }
        if batteryCount == 0 {
            return ""
        }
        return String(format: " · %.0fx", batteryCount)
    }

    private func fetchFleetAPIData() {
        if accessToken == "" {
            errorMessage = "Must log in first"
            return
        }
        guard let energySiteId = energySiteId,
              let url = URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/energy_sites/\(energySiteId)/live_status") else {
            errorMessage = "Must select an energy site first"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        fleetURLSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: FleetEnergySiteResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = "Failed to fetch Fleet API data: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] data in
                let powerwall = PowerwallData(
                    battery: PowerwallData.Battery(instantPower: data.response.batteryPower, count: 0),
                    load: PowerwallData.Load(instantPower: data.response.loadPower),
                    solar: PowerwallData.Solar(instantPower: data.response.solarPower, energyExported: 0),
                    site: PowerwallData.Site(instantPower: data.response.gridPower)
                )
                self?.data = powerwall
                self?.batteryPercentage = BatteryPercentage(percentage: data.response.batteryPercentage)
                self?.gridStatus = GridStatus(status: data.response.gridStatus)
            }
            .store(in: &cancellables)
    }
}

// MARK: - Data Models

struct TokenResponse: Codable {
    let access_token: String
}

struct ProductsResponse: Codable {
    let response: [Product]
    let count: Int
}

struct Product: Codable {
    let deviceType: String?
    let energySiteId: Int?
    let siteName: String?

    enum CodingKeys: String, CodingKey {
        case deviceType = "device_type"
        case energySiteId = "energy_site_id"
        case siteName = "site_name"
    }
}

// Fleet response model
struct FleetEnergySiteResponse: Codable {
    let response: FleetLiveStatus
}

struct FleetLiveStatus: Codable {
    let batteryPower: Double
    let batteryPercentage: Double
    let solarPower: Double
    let loadPower: Double
    let gridPower: Double
    let gridStatus: String

    enum CodingKeys: String, CodingKey {
        case batteryPower = "battery_power"
        case batteryPercentage = "percentage_charged"
        case solarPower = "solar_power"
        case loadPower = "load_power"
        case gridPower = "grid_power"
        case gridStatus = "grid_status"
    }
}

// Define the data model (adjust according to your API response)
struct PowerwallData: Codable {
    struct Battery: Codable {
        let instantPower: Double
        let count: Double

        enum CodingKeys: String, CodingKey {
            case instantPower = "instant_power"
            case count = "num_meters_aggregated"
        }
    }
    let battery: Battery

    struct Load: Codable {
        let instantPower: Double

        enum CodingKeys: String, CodingKey {
            case instantPower = "instant_power"
        }
    }
    let load: Load

    struct Solar: Codable {
        let instantPower: Double
        let energyExported: Double

        enum CodingKeys: String, CodingKey {
            case instantPower = "instant_power"
            case energyExported = "energy_exported"
        }
    }
    let solar: Solar

    struct Site: Codable {
        let instantPower: Double

        enum CodingKeys: String, CodingKey {
            case instantPower = "instant_power"
        }
    }
    let site: Site
}

// Data model for battery percentage
struct BatteryPercentage: Codable {
    let percentage: Double
}

// Data model for grid status
struct GridStatus: Codable {
    let status: String

    enum CodingKeys: String, CodingKey {
        case status = "grid_status"
    }
}
