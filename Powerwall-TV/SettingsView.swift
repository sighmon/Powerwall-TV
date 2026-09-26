//
//  SettingsView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//


import SwiftUI

struct SettingsView: View {
    @Binding var loginMode: LoginMode
    @Binding var ipAddress: String
    @Binding var wallConnectorIPAddress: String
    @Binding var username: String
    @Binding var password: String
    @Binding var accessToken: String
    @Binding var fleetBaseURL: String
    @Binding var electricityMapsAPIKey: String
    @Binding var electricityMapsZone: String
    @Binding var preventScreenSaver: Bool
    @Binding var showLessPrecision: Bool
    @Binding var alwaysShowPowerwallRuntimeEstimate: Bool
    @Binding var showVehicles: Bool
    @Binding var showSchedulerButton: Bool
    @Binding var showInMenuBar: Bool
    @Binding var keepWindowInFront: Bool
    @Binding var autoHideSummaryOnOverlap: Bool
    @Binding var autoHideButtonsOnOverlap: Bool
    @Binding var sceneScale: Double
    @Binding var sceneHorizontalOffset: Double
    @Binding var sceneVerticalOffset: Double
    @Binding var lastChargingWallConnectorVIN: String
    @State var showingConfirmation: Bool
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: PowerwallViewModel

    @State private var exportWeatherLocation = ""
    @State private var keychainError: String?
    @State private var xaiAPIKey = KeychainWrapper.standard.string(forKey: "xai_apiKey") ?? ""
    @AppStorage("exportAdvisor_peakEnd") private var exportPeakEnd = 10
    @AppStorage("exportAdvisor_voice") private var exportVoice = true
    @AppStorage("homeEnergyAdvisor_showButton") private var showHomeEnergyAdvisorButton = false
    @AppStorage("homeEnergyAdvisor_defaultPrompt") private var advisorDefaultPrompt = HomeEnergyAdvisorPreferences.defaultPrompt

    private enum SettingsTab: String, CaseIterable {
        case connection = "Connect", display = "Display", advisor = "Advisor", about = "About"
    }
    @AppStorage("homeEnergyAdvisor_voiceID") private var advisorVoiceID = "luna"
    @State private var grokVoices: [GrokAdvisorClient.Voice] = []
    @State private var loadingVoices = false
    @State private var voiceError: String?
    @State private var voiceReload = 0
    @State private var selectedTab: SettingsTab = .connection

    var body: some View {
        ZStack {
#if !os(tvOS)
            Rectangle().fill(.background)
                .ignoresSafeArea()
            LinearGradient(colors: [.blue.opacity(0.12), .cyan.opacity(0.06), .purple.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
#endif
            VStack(spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Settings").font(.title2.weight(.semibold))
                        Text("Make yourself at home.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Save") { saveAndDismiss() }
                        .buttonStyle(.borderedProminent)
#if !os(tvOS)
                        .keyboardShortcut(.defaultAction)
#endif
                }
                .padding(.horizontal, 24)
                Picker("Settings category", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 24)
                if let keychainError {
                    Text(keychainError).font(.callout).foregroundStyle(.red).padding(.horizontal, 24)
                }
                formContent
            }
            .padding(.top, 24)
#if os(tvOS)
            .frame(maxWidth: 1400)
#endif
        }
#if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
#if os(macOS)
        .frame(minWidth: 580, idealWidth: 660, minHeight: 580, idealHeight: 740)
#endif
        .task(id: [selectedTab.rawValue, xaiAPIKey, String(voiceReload)]) {
            guard selectedTab == .advisor else { return }
            loadingVoices = true
            voiceError = nil
            grokVoices = []
            do {
                // Debounce API-key edits and cancel requests when leaving the tab.
                try await Task.sleep(for: .milliseconds(350))
                let key = xaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else {
                    voiceError = "Add an xAI API key to load available voices."
                    loadingVoices = false
                    return
                }
                let voices = try await GrokAdvisorClient(apiKey: key).voices()
                try Task.checkCancellation()
                grokVoices = voices
                loadingVoices = false
            } catch {
                guard !Task.isCancelled else { return }
                voiceError = "Could not load Grok voices. \(error.localizedDescription)"
                loadingVoices = false
            }
        }
        .onAppear {
            if let siteID = viewModel.energySiteId {
                exportWeatherLocation = UserDefaults.standard.string(forKey: "exportAdvisor_weatherLocation_" + siteID) ?? ""
            }
        }
    }

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 16, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .modifier(AdvisorGlassCard(cornerRadius: 24))
    }

    @ViewBuilder
    private var formContent: some View {
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            if selectedTab == .connection {
            // Section for selecting login mode
            settingsCard("Login Mode") {
                Picker("Mode", selection: $loginMode) {
                    Text("Local").tag(LoginMode.local)
                    Text("Fleet API").tag(LoginMode.fleetAPI)
                }
                .pickerStyle(SegmentedPickerStyle())
            }

            // Gateway settings section, shown only for local mode
            if loginMode == .local {
                settingsCard("Gateway Settings") {
                    Text("IP Address").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("IP Address", text: $ipAddress)
                        .textContentType(.URL)
#if os(iOS) || os(tvOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
#endif
                    Text("Username").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("Username", text: $username)
                        .textContentType(.username)
                    Text("Password").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
                settingsCard("Wall Connector Settings") {
                    Text("IP Address").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    TextField("IP Address", text: $wallConnectorIPAddress)
                        .textContentType(.URL)
                }
            } else {
                settingsCard("Fleet API Settings") {
                    Text("Access token").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    SecureField("Access token", text: $accessToken)
                        .textContentType(.password)
                    Button("Login with your Tesla account") {
                        _ = viewModel.startFleetLoginManually()
                    }
                    Text("Re-login after upgrading to grant vehicle charge data access.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            }

            settingsCard("Wall Connector") {
            LabeledContent("Last charging VIN") {
                Text(lastChargingWallConnectorVIN.isEmpty ? "-" : lastChargingWallConnectorVIN)
#if os(macOS)
                    .textSelection(.enabled)
#endif
            }

            }

            // Electricity Maps connection
            settingsCard("Electricity Maps Settings") {
                Text("API key").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                SecureField("API key", text: $electricityMapsAPIKey)
                    .textContentType(.password)
                Text("Zone (e.g. AU-SA)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("Zone (e.g. AU-SA)", text: $electricityMapsZone)
            }

            }
            if selectedTab == .advisor {
            settingsCard("Home Energy Advisor") {
                Toggle("Show magic button on Home", isOn: $showHomeEnergyAdvisorButton)
                    .accessibilityIdentifier("homeEnergyAdvisorVisibility")
                Text("Default prompt").font(.subheadline.weight(.semibold))
#if os(tvOS)
                TextField("Default prompt", text: $advisorDefaultPrompt)
                    .accessibilityIdentifier("homeEnergyAdvisorPrompt")
#else
                TextEditor(text: $advisorDefaultPrompt)
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Default prompt")
                    .accessibilityIdentifier("homeEnergyAdvisorPrompt")
#endif
                Button("Reset default prompt") { advisorDefaultPrompt = HomeEnergyAdvisorPreferences.defaultPrompt }
                Text("The first question asked when you refresh the advisor. Live energy and weather data are added automatically. An empty prompt uses the default.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("xAI API key").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                SecureField("xAI API key", text: $xaiAPIKey)
                    .textContentType(.password)
                    .accessibilityLabel("xAI API key")
                    .accessibilityIdentifier("exportAdvisorAPIKey")
                Text("Weather location (suburb, country)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                TextField("Weather location (suburb, country)", text: $exportWeatherLocation)
                    .accessibilityLabel("Weather location")
                Text("Used for the selected site when Tesla does not supply coordinates.")
                    .font(.footnote)
                Picker("Morning peak ends (site time)", selection: $exportPeakEnd) {
                    ForEach(0...12, id: \.self) { hour in Text("\(hour):00").tag(hour) }
                }
                Toggle("Speak answers with Grok Voice", isOn: $exportVoice)
                Picker("Grok voice", selection: $advisorVoiceID) {
                    if !grokVoices.contains(where: { $0.id == advisorVoiceID }) {
                        Text(advisorVoiceID.capitalized + " (saved)").tag(advisorVoiceID)
                    }
                    ForEach(grokVoices) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
#if !os(tvOS)
                .pickerStyle(.menu)
#endif
                .accessibilityIdentifier("advisorVoicePicker")
                .disabled(loadingVoices || grokVoices.isEmpty)
                if loadingVoices {
                    ProgressView("Loading Grok voices…").font(.caption)
                        .accessibilityIdentifier("advisorVoicesLoading")
                }
                if let voiceError {
                    Text(voiceError).font(.caption).foregroundStyle(.secondary)
                    Button("Retry loading voices") { voiceReload += 1 }
                }
                Text("Weather and energy estimates work without a key. Adding a key enables Grok’s summary, follow-up questions and spoken answers. When requested, your battery status, recent usage, local forecast and questions are sent to xAI. Your key is stored in Keychain. Requires Fleet API and WeatherKit access. Estimates do not export energy automatically.")
                    .font(.footnote)
            }

            }
            if selectedTab == .display {
            settingsCard("Display Settings") {
#if os(macOS)
                Toggle("Show in menu bar", isOn: $showInMenuBar)
                Toggle("Keep window in front", isOn: $keepWindowInFront)
#endif
#if !os(tvOS)
                Toggle("Auto-hide home summary", isOn: $autoHideSummaryOnOverlap)
                Toggle("Auto-hide buttons", isOn: $autoHideButtonsOnOverlap)
#endif
                Toggle("Limit data to one decimal place", isOn: $showLessPrecision)
                Toggle("Always show Powerwall estimate", isOn: $alwaysShowPowerwallRuntimeEstimate)
                Toggle("Show schedule (beta)", isOn: $showSchedulerButton)
                // For debugging vehicles on accounts without a v3 wall connector
                // Toggle("Show vehicles", isOn: $showVehicles)
                Toggle("Prevent screen saver from showing", isOn: $preventScreenSaver)
                if preventScreenSaver {
                    Text("Warning: keeping the screen on may increase power usage and risk burn-in.")
                            .font(.footnote)
                            .foregroundColor(.gray)
                }
            }

#if !os(tvOS)
            settingsCard("Scene Layout") {
                Stepper("Scene scale: \(Int((clampSceneScale(sceneScale) * 100).rounded()))%", value: $sceneScale, in: sceneScaleRange, step: sceneScaleStep)
                Stepper("Horizontal offset: \(String(format: "%+.0f%%", clampSceneHorizontalOffset(sceneHorizontalOffset) * 100))", value: $sceneHorizontalOffset, in: sceneHorizontalOffsetRange, step: sceneHorizontalOffsetStep)
                Stepper("Vertical offset: \(String(format: "%+.0f%%", clampSceneVerticalOffset(sceneVerticalOffset) * 100))", value: $sceneVerticalOffset, in: sceneVerticalOffsetRange, step: sceneVerticalOffsetStep)
                Button("Reset scene layout") {
                    sceneScale = 1.0
                    sceneHorizontalOffset = 0.0
                    sceneVerticalOffset = 0.0
                }
            }
#endif

            }
            if selectedTab == .about {
            if loginMode == .fleetAPI {
                settingsCard("Delete all settings") {
                    Button("Delete") {
                            showingConfirmation = true
                        }
                        .confirmationDialog(
                            "Are you sure you want to delete all settings?",
                            isPresented: $showingConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                clearAllSettings()
                            }
                            Button("Cancel", role: .cancel) { }
                        }
                }
            }

            settingsCard("Information") {
                Group {
                    Text("Version: \(appVersionAndBuild())")
                    Text("Firmware: \(viewModel.version ?? "-")")
                    Text("Installed: \(viewModel.installationDate?.formatted(date: .long, time: .omitted) ?? "-")")
                    Text("Base: \(fleetBaseURL)")
                        .padding(.bottom, 8)
                    Text("This is an unofficial app – not affiliated with Tesla, Inc. Tesla, Powerwall, and related marks are trademarks of Tesla, Inc.")
                }
                .font(.footnote)
                .opacity(0.6)
#if os(macOS)
                .textSelection(.enabled)
#endif
            }
            }
          }
#if !os(tvOS)
          .textFieldStyle(.roundedBorder)
#endif
          .padding(.horizontal, 24)
          .padding(.bottom, 24)
#if os(tvOS)
          .frame(maxWidth: 1400)
#else
          .frame(maxWidth: 800)
#endif
          .frame(maxWidth: .infinity)
        }
        .id(selectedTab)
    }
    // MARK: – Actions
    private func saveAndDismiss() {
        guard KeychainWrapper.standard.set(xaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "xai_apiKey") else {
            keychainError = "Could not save the xAI key to Keychain. Unlock Keychain and try again."
            return
        }
        keychainError = nil
        if let siteID = viewModel.energySiteId {
            UserDefaults.standard.set(exportWeatherLocation.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "exportAdvisor_weatherLocation_" + siteID)
        }
        sceneScale = clampSceneScale(sceneScale)
        sceneHorizontalOffset = clampSceneHorizontalOffset(sceneHorizontalOffset)
        sceneVerticalOffset = clampSceneVerticalOffset(sceneVerticalOffset)
        UserDefaults.standard.set(loginMode.rawValue, forKey: "loginMode")
        if loginMode == .local {
            UserDefaults.standard.set(ipAddress, forKey: "gatewayIP")
            UserDefaults.standard.set(wallConnectorIPAddress, forKey: "wallConnectorIP")
            UserDefaults.standard.set(username, forKey: "username")
            KeychainWrapper.standard.set(password, forKey: "gatewayPassword")
        } else {
            KeychainWrapper.standard.set(accessToken, forKey: "fleetAPI_accessToken")
        }
        KeychainWrapper.standard.set(electricityMapsAPIKey, forKey: "electricityMaps_apiKey")
        UserDefaults.standard.set(electricityMapsZone, forKey: "electricityMaps_zone")
        UserDefaults.standard.set(preventScreenSaver, forKey: "preventScreenSaver")
        UserDefaults.standard.set(showLessPrecision, forKey: "showLessPrecision")
        UserDefaults.standard.set(alwaysShowPowerwallRuntimeEstimate, forKey: "alwaysShowPowerwallRuntimeEstimate")
        UserDefaults.standard.set(showVehicles, forKey: "showVehicles")
        UserDefaults.standard.set(showSchedulerButton, forKey: "showSchedulerButton")
        UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar")
        UserDefaults.standard.set(keepWindowInFront, forKey: "keepWindowInFront")
        UserDefaults.standard.set(autoHideSummaryOnOverlap, forKey: "autoHideSummaryOnOverlap")
        UserDefaults.standard.set(autoHideButtonsOnOverlap, forKey: "autoHideButtonsOnOverlap")
        UserDefaults.standard.set(clampSceneScale(sceneScale), forKey: "sceneScale")
        UserDefaults.standard.set(clampSceneHorizontalOffset(sceneHorizontalOffset), forKey: "sceneHorizontalOffset")
        UserDefaults.standard.set(clampSceneVerticalOffset(sceneVerticalOffset), forKey: "sceneVerticalOffset")
        viewModel.fetchElectricityMapsData()
        presentationMode.wrappedValue.dismiss()
    }

    private func clearAllSettings() {
        xaiAPIKey = ""
        KeychainWrapper.standard.set("", forKey: "xai_apiKey")
        accessToken = ""
        KeychainWrapper.standard.set("", forKey: "fleetAPI_accessToken")
        KeychainWrapper.standard.set("", forKey: "fleetAPI_refreshToken")
        KeychainWrapper.standard.set("", forKey: "electricityMaps_apiKey")
        UserDefaults.standard.removeObject(forKey: "currentEnergySiteIndex")
        UserDefaults.standard.removeObject(forKey: "fleetAPI_tokenExpiration")
        UserDefaults.standard.removeObject(forKey: "fleetBaseURL")
        UserDefaults.standard.removeObject(forKey: "fleetEnergySiteNames")
        UserDefaults.standard.removeObject(forKey: "electricityMaps_zone")
        UserDefaults.standard.removeObject(forKey: "keepWindowInFront")
        UserDefaults.standard.removeObject(forKey: "autoHideSummaryOnOverlap")
        UserDefaults.standard.removeObject(forKey: "autoHideButtonsOnOverlap")
        UserDefaults.standard.removeObject(forKey: "showVehicles")
        UserDefaults.standard.removeObject(forKey: "alwaysShowPowerwallRuntimeEstimate")
        UserDefaults.standard.removeObject(forKey: "showSchedulerButton")
        UserDefaults.standard.removeObject(forKey: "sceneScale")
        UserDefaults.standard.removeObject(forKey: "sceneHorizontalOffset")
        UserDefaults.standard.removeObject(forKey: "sceneVerticalOffset")
        UserDefaults.standard.removeObject(forKey: "lastChargingWallConnectorVIN")
        viewModel.clearVehicleChargeCache()
        keepWindowInFront = false
        autoHideSummaryOnOverlap = true
        autoHideButtonsOnOverlap = true
        showVehicles = false
        alwaysShowPowerwallRuntimeEstimate = false
        showSchedulerButton = false
        sceneScale = 1.0
        sceneHorizontalOffset = 0.0
        sceneVerticalOffset = 0.0
        lastChargingWallConnectorVIN = ""
    }
}

func appVersionAndBuild() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    return "\(version) (\(build))"
}

// Preview provider (optional, for testing)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView(
            loginMode: .constant(LoginMode.local),
            ipAddress: .constant("192.168.1.100"),
            wallConnectorIPAddress: .constant("192.168.1.101"),
            username: .constant("user@example.com"),
            password: .constant("password"),
            accessToken: .constant("accessToken"),
            fleetBaseURL: .constant("https://fleet-api.prd.na.vn.cloud.tesla.com"),
            electricityMapsAPIKey: .constant(""),
            electricityMapsZone: .constant(""),
            preventScreenSaver: .constant(false),
            showLessPrecision: .constant(false),
            alwaysShowPowerwallRuntimeEstimate: .constant(false),
            showVehicles: .constant(true),
            showSchedulerButton: .constant(true),
            showInMenuBar: .constant(false),
            keepWindowInFront: .constant(false),
            autoHideSummaryOnOverlap: .constant(true),
            autoHideButtonsOnOverlap: .constant(true),
            sceneScale: .constant(1.0),
            sceneHorizontalOffset: .constant(0.0),
            sceneVerticalOffset: .constant(0.0),
            lastChargingWallConnectorVIN: .constant(""),
            showingConfirmation: false,
            viewModel: PowerwallViewModel()
        )
    }
}
