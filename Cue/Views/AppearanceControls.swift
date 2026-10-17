import SwiftUI

/// Font, text size, theme and opacity. Shown in the window's appearance popover
/// and as the Settings window, so both always offer the same choices.
struct AppearanceControls: View {
    @AppStorage("defaultTextSize") private var textSize: Double = 18
    @AppStorage("backgroundOpacity") private var backgroundOpacity: Double = 0.92
    @AppStorage("fontFamily") private var fontFamily: String = PrompterFont.system
    @AppStorage("theme") private var theme: PrompterTheme = .dark
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("Font") {
                Picker("Font", selection: Binding(get: { PrompterFont.choice(fontFamily) }, set: { fontFamily = $0 })) {
                    ForEach(PrompterFont.choices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            row("Size") {
                Slider(value: $textSize, in: 12...72)
                Text("\(Int(textSize)) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("Theme")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(PrompterTheme.allCases) { option in
                        Button { theme = option } label: {
                            ThemeSwatch(theme: option, resolved: option.resolved(for: colorScheme), isSelected: option == theme)
                        }
                        .buttonStyle(.plain)
                        .help(option.name)
                        .accessibilityLabel("\(option.name) theme")
                        .accessibilityAddTraits(option == theme ? .isSelected : [])
                    }
                }
            }

            row("Opacity") {
                // Floor at 0.5: below it the text gets hard to read over what's behind
                Slider(value: $backgroundOpacity, in: 0.5...1.0)
                Text(String(format: "%.0f%%", backgroundOpacity * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            label(title).frame(width: 56, alignment: .leading)
            content()
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

/// A small sample of a theme: "Aa" in its text color on its background.
private struct ThemeSwatch: View {
    let theme: PrompterTheme
    let resolved: PrompterTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("Aa")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(nsColor: resolved.text))
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(Color(nsColor: resolved.background), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: isSelected ? 2.5 : 1)
                )
            Text(theme == .system ? "System" : theme.name)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    AppearanceControls()
        .padding(16)
        .frame(width: 320)
}
