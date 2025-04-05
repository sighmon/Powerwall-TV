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
    @Binding var username: String
    @Binding var password: String
    @Binding var accessToken: String
    @Binding var preventScreenSaver: Bool
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                // Section for selecting login mode
                Section(header: Text("Login Mode")) {
                    Picker("Mode", selection: $loginMode) {
                        Text("Local").tag(LoginMode.local)
                        Text("Fleet API").tag(LoginMode.fleetAPI)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                // Gateway settings section, shown only for local mode
                if loginMode == .local {
                    Section(header: Text("Gateway Settings")) {
                        TextField("IP Address", text: $ipAddress)
                            .textContentType(.URL)
                        TextField("Username", text: $username)
                            .textContentType(.username)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    }
                } else {
                    Section(header: Text("Fleet API Settings")) {
                        SecureField("Access token", text: $accessToken)
                            .textContentType(.password)
                    }
                }

                // New section for screen saver prevention
                Section(header: Text("Display Settings")) {
                    Toggle("Prevent screen saver from showing", isOn: $preventScreenSaver)
                    if preventScreenSaver {
                        Text("Warning: keeping the screen on may increase power usage and risk burn-in.")
                                .font(.footnote)
                                .foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Save login mode to UserDefaults
                        UserDefaults.standard.set(loginMode.rawValue, forKey: "loginMode")

                        // Save settings
                        if loginMode == .local {
                            UserDefaults.standard.set(ipAddress, forKey: "gatewayIP")
                            UserDefaults.standard.set(username, forKey: "username")
                            KeychainWrapper.standard.set(password, forKey: "gatewayPassword")
                        }
                        if loginMode == .fleetAPI {
                            KeychainWrapper.standard.set(accessToken, forKey: "fleetAPI_accessToken")
                        }

                        UserDefaults.standard.set(preventScreenSaver, forKey: "preventScreenSaver")

                        // Dismiss the settings view
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        Text(appVersionAndBuild())
            .font(.footnote)
            .opacity(0.6)
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
            username: .constant("user@example.com"),
            password: .constant("password"),
            accessToken: .constant("accessToken"),
            preventScreenSaver: .constant(false)
        )
    }
}
