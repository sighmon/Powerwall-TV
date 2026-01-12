//
//  PowerwallViewModel.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//


import Foundation
import Combine
import AuthenticationServices

enum LoginMode: String, CaseIterable {
    case local = "local"
    case fleetAPI = "fleetAPI"
}

class PowerwallViewModel: ObservableObject {
    // Published properties for UI binding

    // Local login
    @Published var loginMode: LoginMode = LoginMode(rawValue: UserDefaults.standard.string(forKey: "loginMode") ?? "local") ?? .local
    @Published var ipAddress: String = UserDefaults.standard.string(forKey: "gatewayIP") ?? ""
    @Published var wallConnectorIPAddress: String = UserDefaults.standard.string(forKey: "wallConnectorIP") ?? ""
    @Published var username: String = UserDefaults.standard.string(forKey: "username") ?? "customer"
    @Published var password: String = KeychainWrapper.standard.string(forKey: "gatewayPassword") ?? ""
    @Published var preventScreenSaver: Bool = UserDefaults.standard.bool(forKey: "preventScreenSaver")
    @Published var showLessPrecision: Bool = UserDefaults.standard.bool(forKey: "showLessPrecision")
    @Published var showInMenuBar: Bool = UserDefaults.standard.bool(forKey: "showInMenuBar")
    @Published var currentEnergySiteIndex: Int = UserDefaults.standard.integer(forKey: "currentEnergySiteIndex")
    @Published var energySites: [Product] = []

    @Published var data: PowerwallData?
    @Published var batteryPercentage: BatteryPercentage?
    @Published var gridStatus: GridStatus?
    @Published var errorMessage: String?

    // Tesla Fleet API credentials (replace with your actual values)
    private let clientID = Secrets.clientID
    private let clientSecret = Secrets.clientSecret
    private let redirectURI = "powerwalltv://app/callback"
    private let scopes = "openid energy_device_data offline_access"
    private var wiggleWatts = 10.0

    // Fleet API-specific properties
    @Published var accessToken: String = KeychainWrapper.standard.string(forKey: "fleetAPI_accessToken") ?? ""
    @Published var energySiteId: String?
    @Published var siteName: String?
    @Published var batteryPowerHistory: [HistoricalDataPoint] = []
    @Published var batteryPercentageHistory: [HistoricalDataPoint] = []
    @Published var currentEndDate: Date = Date()
    @Published var solarEnergyTodayWh: Double?
    @Published var batteryCount: Double?
    @Published var version: String?
    @Published var installationDate: Date?
    private var fleetRegionResolved: Bool = false
    @Published var fleetBaseURL: String = UserDefaults.standard.string(forKey: "fleetBaseURL") ?? "https://fleet-api.prd.na.vn.cloud.tesla.com"

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private var cancellables = Set<AnyCancellable>()

    // URLSession instances
    private let localURLSession: URLSession  // For local, insecure connections
    private let fleetURLSession: URLSession = {  // For Fleet API
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 9 // seconds (e.g., request-level timeout)
        config.timeoutIntervalForResource = 9 // seconds (e.g., download task timeout)
        return URLSession(configuration: config)
    }()

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
#if os(macOS)
        authSession.presentationContextProvider = self
#endif
        authSession.start()
    }

    private func exchangeCodeForToken(code: String) {
        guard let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token") else {
            errorMessage = "Invalid token URL"
            return
        }

        let usedAudience = fleetBaseURL

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=authorization_code&client_id=\(clientID)&client_secret=\(clientSecret)&code=\(code)&redirect_uri=\(redirectURI)&audience=\(fleetBaseURL)"
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
                if let refreshToken = tokenResponse.refresh_token {
                    KeychainWrapper.standard.set(refreshToken, forKey: "fleetAPI_refreshToken")
                }
                if let expiresIn = tokenResponse.expires_in {
                    let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
                    UserDefaults.standard.set(expirationDate, forKey: "fleetAPI_tokenExpiration")
                }
                self.resolveRegionBaseURL()
                if self.fleetBaseURL != usedAudience {
                    // Clear tokens and re-login with correct audience
                    self.accessToken = ""
                    KeychainWrapper.standard.set("", forKey: "fleetAPI_accessToken")
                    KeychainWrapper.standard.set("", forKey: "fleetAPI_refreshToken")
                    UserDefaults.standard.removeObject(forKey: "currentEnergySiteIndex")
                    UserDefaults.standard.removeObject(forKey: "fleetAPI_tokenExpiration")
                    self.loginWithTeslaFleetAPI()
                } else {
                    self.fetchEnergyProducts()
                }
            }
        }.resume()
    }

    private func refreshAccessToken() {
        guard let refreshToken = KeychainWrapper.standard.string(forKey: "fleetAPI_refreshToken") else {
            errorMessage = "No refresh token available"
            loginWithTeslaFleetAPI() // Fallback to full login
            return
        }

        guard let tokenURL = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token") else {
            errorMessage = "Invalid token URL"
            return
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "grant_type=refresh_token&client_id=\(clientID)&client_secret=\(clientSecret)&refresh_token=\(refreshToken)"
        request.httpBody = body.data(using: .utf8)

        fleetURLSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Token refresh failed: \(error.localizedDescription)"
                    self.loginWithTeslaFleetAPI() // Fallback to full login
                }
                return
            }

            guard let data = data,
                  let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to decode token response"
                    self.loginWithTeslaFleetAPI()
                }
                return
            }

            DispatchQueue.main.async {
                self.accessToken = tokenResponse.access_token
                KeychainWrapper.standard.set(tokenResponse.access_token, forKey: "fleetAPI_accessToken")
                if let refreshToken = tokenResponse.refresh_token { // Some APIs issue new refresh tokens
                    KeychainWrapper.standard.set(refreshToken, forKey: "fleetAPI_refreshToken")
                }
                if let expiresIn = tokenResponse.expires_in {
                    let expirationDate = Date().addingTimeInterval(TimeInterval(expiresIn))
                    UserDefaults.standard.set(expirationDate, forKey: "fleetAPI_tokenExpiration")
                }
                self.resolveRegionBaseURL()
                self.fetchFleetAPIData() // Retry the failed request
            }
        }.resume()
    }

    private func resolveRegionBaseURL() {
        if fleetRegionResolved || accessToken.isEmpty { return }

        let candidates = [
            "https://fleet-api.prd.na.vn.cloud.tesla.com",
            "https://fleet-api.prd.eu.vn.cloud.tesla.com"
        ]

        for base in candidates {
            var request = URLRequest(url: URL(string: "\(base)/api/1/users/region")!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

            let semaphore = DispatchSemaphore(value: 0)

            fleetURLSession.dataTask(with: request) { data, resp, err in
                defer { semaphore.signal() }

                let http = resp as? HTTPURLResponse
                let code = http?.statusCode ?? -1
                #if DEBUG
                print("Region probe → \(base) status=\(code) error=\(String(describing: err))")
                #endif

                guard err == nil, code == 200, let data = data else {
                    // Log body for non-200s too
                    #if DEBUG
                    if let data = data {
                        print("Region probe body (\(base)):\n", String(data: data, encoding: .utf8) ?? data.map { String(format:"%02x", $0) }.joined())
                    }
                    #endif
                    return
                }

                do {
                    let info = try JSONDecoder().decode(RegionResponse.self, from: data)
                    if let url = info.response.fleet_api_base_url, !url.isEmpty {
                        DispatchQueue.main.async {
                            self.fleetBaseURL = url
                            self.fleetRegionResolved = true
                            UserDefaults.standard.set(self.fleetBaseURL, forKey: "fleetBaseURL")
                            #if DEBUG
                            print("Resolved fleet base URL → \(url)")
                            #endif
                        }
                    } else {
                        #if DEBUG
                        print("Decoded RegionResponse but fleet_api_base_url was empty/null")
                        #endif
                    }
                } catch {
                    #if DEBUG
                    print("Region decode failed: \(error)")
                    print("Raw body:\n", String(data: data, encoding: .utf8) ?? data.map { String(format:"%02x", $0) }.joined())
                    #endif
                }
            }.resume()

            _ = semaphore.wait(timeout: .now() + 2) // quick try

            if fleetRegionResolved { break }
        }
    }

    private func fetchEnergyProducts() {
        if accessToken.isEmpty {
            errorMessage = "No access token available"
            return
        }

        guard let url = URL(string: "\(fleetBaseURL)/api/1/products") else {
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
            .sink { [weak self] completionResult in
                if case .failure(let error) = completionResult {
                    self?.errorMessage = "Failed to fetch products: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] productsResponse in
                guard let self = self else { return }
                let energySites = productsResponse.response.filter { $0.energySiteId != nil }
                self.energySites = energySites
                if energySites.isEmpty {
                    self.errorMessage = "No energy products found"
                } else {
                    // Adjust index if out of bounds
                    if self.currentEnergySiteIndex >= energySites.count {
                        self.currentEnergySiteIndex = 0
                        UserDefaults.standard.set(0, forKey: "currentEnergySiteIndex")
                    }
                    self.fetchData()
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Fetching

    func fetchData() {
        self.errorMessage = nil
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
            if accessToken.isEmpty {
                // No token, initiate login
                login { success in
                    if success {
                        self.fetchEnergyProducts()
                    }
                    // If login fails, errorMessage is already set by the login function
                }
            }
            if let expirationDate = UserDefaults.standard.object(forKey: "fleetAPI_tokenExpiration") as? Date,
               Date() >= expirationDate {
                self.refreshAccessToken()
            }
            self.resolveRegionBaseURL()
            if !self.energySites.isEmpty {
                let currentSite = self.energySites[self.currentEnergySiteIndex]
                if let id = currentSite.energySiteId {
                    self.energySiteId = String(id)
                    self.siteName = currentSite.siteName ?? "Energy Site \(id)"
                    self.fetchFleetAPIData()
                    if self.solarEnergyTodayWh == nil {
                        self.fetchSolarEnergyToday()
                    }
                    if self.batteryCount == nil {
                        self.fetchSiteInfo()
                    }
                } else {
                    self.errorMessage = "No energy_site_id on selected product"
                }
            } else {
                self.fetchEnergyProducts()
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
                guard let self = self else { return }
                self.data = data
                self.fetchLocalWallConnectorVitalsAndMerge(into: data)
            }
            .store(in: &cancellables)
    }

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

    private func fetchLocalWallConnectorVitalsAndMerge(into base: PowerwallData) {
        let wallConnectorIP = wallConnectorIPAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wallConnectorIP.isEmpty else {
            return
        }

        guard let url = URL(string: "https://\(wallConnectorIP)/api/1/vitals") else {
            self.errorMessage = "Invalid Wall Connector vitals URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        localURLSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: WallConnectorVitals.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                if case .failure(let error) = completion {
                    // Don’t wipe existing Powerwall data if WC fails; just attach an error.
                    self.errorMessage = "Failed to fetch Wall Connector vitals: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] vitals in
                guard let self = self else { return }

                // Map vitals into your existing WallConnector model.
                // vin/din aren't available via vitals; we’ll use the IP as a stable "din".
                let wallConnector = WallConnector(
                    vin: nil,
                    din: wallConnectorIP,
                    wallConnectorState: 0.0, // Double(vitals.evseState), // Note: this doesn't match the Fleet API!
                    wallConnectorPower: vitals.wallConnectorPower
                )

                let merged = PowerwallData(
                    battery: base.battery,
                    load: base.load,
                    solar: base.solar,
                    site: base.site,
                    wallConnectors: [wallConnector]
                )

                self.data = merged
            }
            .store(in: &cancellables)
    }

    func goToPreviousDay() {
        currentEndDate = currentEndDate.addingTimeInterval(-24 * 3600) // Subtract 24 hours
        fetchFleetAPIHistory()
    }

    func goToNextDay() {
        let nextEndDate = currentEndDate.addingTimeInterval(24 * 3600) // Add 24 hours
        let now = Date()
        if nextEndDate > now {
            currentEndDate = now // Clamp to current date/time
        } else {
            currentEndDate = nextEndDate
        }
        fetchFleetAPIHistory()
    }

    // Computed property to display the current date label
    var currentDateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(currentEndDate) {
            return "Today"
        } else if calendar.isDateInYesterday(currentEndDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: currentEndDate)
        }
    }

    // Return 23:59:59 on this day if it's not today so we see full graph data
    private func endOfDayIfNeeded(_ date: Date) -> Date {
        let cal = Calendar.current
        guard !cal.isDateInToday(date) else { return date }

        return cal.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: cal.startOfDay(for: date)
        ) ?? date
    }

    // Updated getHistoryDateRange to use currentEndDate
    private func getHistoryDateRange() -> (start: String, end: String) {
        let effectiveEnd = endOfDayIfNeeded(currentEndDate)
        let end = isoFormatter.string(from: effectiveEnd)
        let start = isoFormatter.string(from: effectiveEnd.addingTimeInterval(-24 * 3600))
        return (start, end)
    }

    private func fetchFleetAPIData() {
        if accessToken == "" {
            errorMessage = "Must log in first"
            return
        }
        guard let energySiteId = energySiteId,
              let url = URL(string: "\(fleetBaseURL)/api/1/energy_sites/\(energySiteId)/live_status") else {
            errorMessage = "No energy site ID, refreshing token"
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
                    if (error as? URLError)?.code == .userAuthenticationRequired {
                        self?.refreshAccessToken() // Attempt to refresh token
                    } else {
                        self?.errorMessage = "Failed to fetch Fleet API data: \(error.localizedDescription)"
                    }
                }
            } receiveValue: { [weak self] data in
                let powerwall = PowerwallData(
                    battery: PowerwallData.Battery(instantPower: data.response.batteryPower, count: self?.batteryCount ?? 0),
                    load: PowerwallData.Load(instantPower: data.response.loadPower),
                    solar: PowerwallData.Solar(instantPower: data.response.solarPower, energyExported: 0),
                    site: PowerwallData.Site(instantPower: data.response.gridPower),
                    wallConnectors: data.response.wallConnectors
                )
                self?.data = powerwall
                self?.batteryPercentage = BatteryPercentage(percentage: data.response.batteryPercentage)
                self?.gridStatus = GridStatus(status: data.response.gridStatus)
            }
            .store(in: &cancellables)
    }

    private func fetchPowerHistory(completion: @escaping (Result<[HistoricalDataPoint], Error>) -> Void) {
        guard let energySiteId = energySiteId else {
            completion(.failure(NSError(domain: "Missing energySiteId", code: 0, userInfo: nil)))
            return
        }

        let (start, end) = getHistoryDateRange()
        let timeZone = TimeZone.current.identifier.isEmpty ? "Etc/UTC" : TimeZone.current.identifier
        let urlString = "\(fleetBaseURL)/api/1/energy_sites/\(energySiteId)/calendar_history?kind=energy&period=day&start_date=\(start)&end_date=\(end)&time_zone=\(timeZone)"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        fleetURLSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0, userInfo: nil)))
                return
            }
            do {
                let powerResponse = try JSONDecoder().decode(PowerHistoryResponse.self, from: data)
                let dataPoints = powerResponse.response.time_series.map { point in
                    HistoricalDataPoint(
                        date: self.isoFormatter.date(from: point.timestamp)!,
                        value: point.batteryPower - point.batteryFromSolar - point.batteryFromGrid,
                        from: (point.batteryFromGrid + self.wiggleWatts) > point.batteryFromSolar ? PowerFrom.grid : PowerFrom.solar,
                        to: point.batteryToGrid > self.wiggleWatts ? PowerTo.grid : PowerTo.home
                    )
                }
                completion(.success(dataPoints))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchSolarEnergyToday() {
        guard let energySiteId = energySiteId else { return }

        // UTC timestamps in ISO-8601 so we match the cloud API
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let start = isoFormatter.string(from: startOfDay)
        let end   = isoFormatter.string(from: Date())
        let tz    = TimeZone.current.identifier.isEmpty ? "Etc/UTC" : TimeZone.current.identifier

        let urlStr = """
            \(fleetBaseURL)/api/1/energy_sites/\
            \(energySiteId)/calendar_history?kind=energy&period=day&\
            start_date=\(start)&end_date=\(end)&time_zone=\(tz)
            """
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        fleetURLSession.dataTask(with: req) { [weak self] data, _, error in
            guard let data = data,
                  let payload = try? JSONDecoder().decode(PowerHistoryResponse.self, from: data)
            else { return }

            let totalWh = payload.response.time_series.reduce(0) { $0 + ($1.solarEnergyExported ?? 0) }

            DispatchQueue.main.async { self?.solarEnergyTodayWh = totalWh }
        }.resume()
    }

    func fetchSiteInfo() {
        guard let energySiteId = energySiteId else { return }

        let urlStr = "\(fleetBaseURL)/api/1/energy_sites/\(energySiteId)/site_info"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        fleetURLSession.dataTask(with: req) { [weak self] data, _, error in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let data = data,
                  let payload = try? decoder.decode(SiteInfoResponse.self, from: data)
            else { return }

            DispatchQueue.main.async {
                self?.batteryCount = payload.response.batteryCount
                self?.version = payload.response.version
                self?.installationDate = payload.response.installationDate
            }
        }.resume()
    }

    private func fetchSOEHistory(completion: @escaping (Result<[HistoricalDataPoint], Error>) -> Void) {
        guard let energySiteId = energySiteId else {
            completion(.failure(NSError(domain: "Missing energySiteId", code: 0, userInfo: nil)))
            return
        }

        let (start, end) = getHistoryDateRange()
        let urlString = "\(fleetBaseURL)/api/1/energy_sites/\(energySiteId)/calendar_history?kind=soe&period=day&start_date=\(start)&end_date=\(end)&time_zone=Australia/Adelaide"
        guard let url = URL(string: urlString) else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        fleetURLSession.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "No data", code: 0, userInfo: nil)))
                return
            }
            do {
                let soeResponse = try JSONDecoder().decode(SOEHistoryResponse.self, from: data)
                let dataPoints = soeResponse.response.time_series.map { point in
                    HistoricalDataPoint(date: self.isoFormatter.date(from: point.timestamp)!, value: point.soe, from: nil, to: nil)
                }
                completion(.success(dataPoints))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func fetchFleetAPIHistory() {
        fetchPowerHistory { result in
            switch result {
            case .success(let dataPoints):
                DispatchQueue.main.async {
                    self.batteryPowerHistory = dataPoints
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to fetch battery power history: \(error.localizedDescription)"
                }
            }
        }

        fetchSOEHistory { result in
            switch result {
            case .success(let dataPoints):
                DispatchQueue.main.async {
                    self.batteryPercentageHistory = dataPoints
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to fetch battery percentage history: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Data Models

struct TokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int?
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
    let wallConnectors: [WallConnector]

    enum CodingKeys: String, CodingKey {
        case batteryPower = "battery_power"
        case batteryPercentage = "percentage_charged"
        case solarPower = "solar_power"
        case loadPower = "load_power"
        case gridPower = "grid_power"
        case gridStatus = "grid_status"
        case wallConnectors = "wall_connectors"
    }
}

struct WallConnector: Codable {
    let vin: String?
    let din: String?
    let wallConnectorState: Double?
    let wallConnectorPower: Double?

    enum CodingKeys: String, CodingKey {
        case vin
        case din
        case wallConnectorState = "wall_connector_state"
        case wallConnectorPower = "wall_connector_power"
    }
}

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
    let wallConnectors: [WallConnector]

    init(
        battery: Battery,
        load: Load,
        solar: Solar,
        site: Site,
        wallConnectors: [WallConnector]? = []
    ) {
        self.battery = battery
        self.load = load
        self.solar = solar
        self.site = site
        self.wallConnectors = wallConnectors ?? []
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        battery = try c.decode(Battery.self, forKey: .battery)
        load    = try c.decode(Load.self,   forKey: .load)
        solar   = try c.decode(Solar.self,  forKey: .solar)
        site    = try c.decode(Site.self,   forKey: .site)
        wallConnectors = try c.decodeIfPresent([WallConnector].self, forKey: .wallConnectors) ?? []
    }
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

struct SiteInfoResponse: Codable {
    let response: SiteInfo
}

struct SiteInfo: Codable {
    let id: String?
    let siteName: String?
    let version: String?
    let batteryCount: Double?
    let installationDate: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case siteName = "site_name"
        case version
        case batteryCount = "battery_count"
        case installationDate = "installation_date"
    }
}

// Historical power data from energy_history with kind="power"
struct PowerHistoryResponse: Codable {
    let response: PowerHistory
}

struct PowerHistory: Codable {
    let time_series: [PowerDataPoint]
}

struct PowerDataPoint: Codable {
    let timestamp: String
    let batteryPower: Double
    let batteryFromSolar: Double
    let batteryFromGrid: Double
    let batteryToGrid: Double
    let solarEnergyExported: Double?

    enum CodingKeys: String, CodingKey {
        case timestamp
        case batteryPower = "battery_energy_exported"
        case batteryFromSolar = "battery_energy_imported_from_solar"
        case batteryFromGrid = "battery_energy_imported_from_grid"
        case batteryToGrid = "grid_energy_exported_from_battery"
        case solarEnergyExported  = "solar_energy_exported"
    }
}

struct SOEHistoryResponse: Codable {
    let response: SOEHistory
}

struct SOEHistory: Codable {
    let time_series: [SOEDataPoint]
}

struct SOEDataPoint: Codable {
    let timestamp: String
    let soe: Double
}

enum PowerFrom: String, CaseIterable {
    case grid = "grid"
    case solar = "solar"
}

enum PowerTo: String, CaseIterable {
    case grid = "grid"
    case home = "home"
}

struct HistoricalDataPoint {
    let date: Date
    let value: Double
    let from: PowerFrom?
    let to: PowerTo?
}

struct RegionResponse: Codable {
    struct RegionInfo: Codable {
        let region: String?
        let fleet_api_base_url: String?
    }
    let response: RegionInfo
}

struct WallConnectorVitals: Codable {
    let contactorClosed: Bool
    let vehicleConnected: Bool
    let session: Int
    let gridVolts: Double
    let gridHertz: Double
    let vehicleCurrentAmps: Double
    let uptime: Int
    let evseState: Int

    enum CodingKeys: String, CodingKey {
        case contactorClosed = "contactor_closed"
        case vehicleConnected = "vehicle_connected"
        case session = "session_s"
        case gridVolts = "grid_v"
        case gridHertz = "grid_hz"
        case vehicleCurrentAmps = "vehicle_current_a"
        case uptime = "uptime_s"
        case evseState = "evse_state"
    }
}

extension WallConnectorVitals {
    // Approximate instantaneous charging power (W).
    // Uses `grid_v * vehicle_current_a` which is a decent single-phase estimate.
    var wallConnectorPower: Double { gridVolts * vehicleCurrentAmps }
}

#if os(macOS)
extension PowerwallViewModel: ASWebAuthenticationPresentationContextProviding {
    func isEqual(_ object: Any?) -> Bool {
        return true
    }

    var hash: Int {
        return 0
    }

    var superclass: AnyClass? {
        return PowerwallViewModel.self
    }

    func `self`() -> Self {
        return self
    }

    func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! {
        return nil
    }

    func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! {
        return nil
    }

    func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! {
        return nil
    }

    func isProxy() -> Bool {
        return true
    }

    func isKind(of aClass: AnyClass) -> Bool {
        return true
    }

    func isMember(of aClass: AnyClass) -> Bool {
        return true
    }

    func conforms(to aProtocol: Protocol) -> Bool {
        return true
    }

    func responds(to aSelector: Selector!) -> Bool {
        return true
    }

    var description: String {
        return "Login with your Tesla account to see your Powerwall statistics"
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
#endif
