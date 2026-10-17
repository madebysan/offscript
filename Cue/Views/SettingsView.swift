import SwiftUI

/// The Settings window holds the same controls as the window's appearance popover.
struct SettingsView: View {
    var body: some View {
        AppearanceControls()
            .padding(20)
            .frame(width: 360)
    }
}

#Preview {
    SettingsView()
}
