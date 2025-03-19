//
//  SettingsView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 17/3/2025.
//


import SwiftUI

struct SettingsView: View {
    @Binding var ipAddress: String
    @Binding var username: String
    @Binding var password: String
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Gateway Settings")) {
                    TextField("IP Address", text: $ipAddress)
                        .textContentType(.URL) // Helps with keyboard input
                    TextField("Username", text: $username)
                        .textContentType(.username)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // Save to UserDefaults and Keychain
                        UserDefaults.standard.set(ipAddress, forKey: "gatewayIP")
                        UserDefaults.standard.set(username, forKey: "username")
                        KeychainWrapper.standard.set(password, forKey: "gatewayPassword")
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}
