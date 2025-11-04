//
//  ScaledContentView.swift
//  Powerwall-TV
//
//  Created by Simon Loffler on 1/11/2025.
//


import SwiftUI
import SwiftData

struct ScaledContentView: View {
    @ObservedObject var viewModel: PowerwallViewModel
    var body: some View {
#if os(macOS)
        GeometryReader { proxy in
            // The size the user has actually given us.
            let availableWidth  = proxy.size.width
            let availableHeight = proxy.size.height

            // Your "design resolution"
            let baseWidth: CGFloat  = 1280
            let baseHeight: CGFloat = 720

            // Calculate a uniform scale that:
            // - is 1.0 at or below base size
            // - grows if the window is larger
            // We clamp at minimum 1 so it never shrinks below 1.
            let scale = max(
                1.0,
                min(availableWidth / baseWidth,
                    availableHeight / baseHeight)
            )

            // Size of the scaled content
            let scaledWidth  = baseWidth * scale
            let scaledHeight = baseHeight * scale

            // Center it in the window
            ZStack {
                // Background color should fill the window
                Color(red: 22/255, green: 23/255, blue: 24/255)
                    .ignoresSafeArea()

                // The designed layout, at base 1280x720 coordinates,
                // then scaled up.
                ContentView(viewModel: viewModel)
                    .frame(width: baseWidth, height: baseHeight)
                    .scaleEffect(scale, anchor: .center)
                    .frame(width: scaledWidth, height: scaledHeight)
            }
            // Make sure the ZStack uses full window space
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
#else
        // tvOS
        ContentView(viewModel: viewModel)
            .ignoresSafeArea()
#endif
    }
}
