import SwiftUI

struct CountdownView: View {
    let value: Int
    var background: Color = .black
    var foreground: Color = .white

    var body: some View {
        Text("\(value)")
            .font(.system(size: 48, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .monospacedDigit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background.opacity(0.55))
            .transition(.opacity)
            .id(value)
    }
}

#Preview {
    CountdownView(value: 3)
        .frame(width: 380, height: 100)
}
