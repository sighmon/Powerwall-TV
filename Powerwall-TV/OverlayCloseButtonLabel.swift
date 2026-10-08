import SwiftUI

/// Keep the visible close symbol and its full 48-point hit target consistent across sheets.
struct OverlayCloseButtonLabel: View {
    var body: some View {
        Image(systemName: "xmark.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 32, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: 48, height: 48)
            .contentShape(Rectangle())
    }
}
