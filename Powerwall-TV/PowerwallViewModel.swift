//
//  PowerwallViewModel.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//


import Foundation
import Combine

class PowerwallViewModel: ObservableObject {
    // Published properties for SwiftUI binding
    @Published var ipAddress: String
    @Published var username: String
    @Published var password: String
    @Published var data: PowerwallData?
    @Published var batteryPercentage: BatteryPercentage?
    @Published var gridStatus: GridStatus?
    @Published var errorMessage: String?
    
    // URLSession instance to manage cookies across requests
    private let urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()

    init(ipAddress: String, username: String = "customer", password: String) {
        self.ipAddress = ipAddress
        self.username = username
        self.password = password
        // Use the shared URLSession to handle cookies automatically
        let delegate = InsecureURLSessionDelegate()
        self.urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }

    // Logs in to the Powerwall gateway to obtain an authentication cookie
    func login(completion: @escaping (Bool) -> Void) {
        // Construct the login URL
        guard let url = URL(string: "https://\(ipAddress)/api/login/Basic") else {
            self.errorMessage = "Invalid login URL"
            completion(false)
            return
        }

        // Create the login payload as a dictionary
        let loginPayload: [String: Any] = [
            "username": "customer",
            "password": password,
            "email": username,
            "force_sm_off": false
        ]

        // Serialize the payload to JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: loginPayload) else {
            self.errorMessage = "Failed to serialize login payload"
            completion(false)
            return
        }

        // Configure the POST request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Perform the login request
        urlSession.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Login failed: \(error.localizedDescription)"
                    completion(false)
                }
                return
            }

            // Verify that we received an AuthCookie in the response
            if let httpResponse = response as? HTTPURLResponse {
                let cookies = HTTPCookie.cookies(withResponseHeaderFields: httpResponse.allHeaderFields as? [String: String] ?? [:], for: url)
                if cookies.contains(where: { $0.name == "AuthCookie" }) {
                    DispatchQueue.main.async {
                        completion(true) // Login successful
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Login failed: No AuthCookie received"
                        completion(false)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Login failed: Invalid response"
                    completion(false)
                }
            }
        }.resume()
    }

    // Fetches data from the Powerwall API after successful login
    func fetchData() {
        // Ensure login before fetching data
        login { success in
            if success {
                self.fetchDataAfterLogin()
                self.fetchBatteryPercentage()
                self.fetchGridStatus()
            }
            // If login fails, errorMessage is already set by the login function
        }
    }

    func isOffGrid() -> Bool {
        return gridStatus?.status ?? "" == "SystemIslandedActive"
    }

    // Private helper to fetch data using the authenticated session
    private func fetchDataAfterLogin() {
        // Construct the data URL (example endpoint: /api/meters/aggregates)
        guard let url = URL(string: "https://\(ipAddress)/api/meters/aggregates") else {
            self.errorMessage = "Invalid data URL"
            return
        }

        // Configure the GET request
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        // Use Combine to fetch and decode the data
        urlSession.dataTaskPublisher(for: request)
            .map { $0.data }
            .decode(type: PowerwallData.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.errorMessage = "Failed to fetch data: \(error.localizedDescription)"
                }
            } receiveValue: { [weak self] data in
                self?.data = data
                self?.errorMessage = nil
            }
            .store(in: &cancellables)
    }

    // Fetches battery percentage from the /api/system_status/soe endpoint
    private func fetchBatteryPercentage() {
        guard let url = URL(string: "https://\(ipAddress)/api/system_status/soe") else {
            self.errorMessage = "Invalid battery percentage URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        urlSession.dataTaskPublisher(for: request)
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
    private func fetchGridStatus() {
        guard let url = URL(string: "https://\(ipAddress)/api/system_status/grid_status") else {
            self.errorMessage = "Invalid grid status URL"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        urlSession.dataTaskPublisher(for: request)
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
