import SwiftUI

/// A search field for the top of a form section, with a spinner while `searching`.
struct SearchField: View {
    var placeholder: String
    @Binding var text: String
    var searching = false
    var autoFocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField(placeholder, text: $text)
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if searching {
                ProgressView()
            } else if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.tertiaryText)
                    .buttonStyle(.plain)
            }
        }
        .onAppear { if autoFocus { focused = true } }
    }
}

/// A row to pick from a list: a colored dot, a title and subtitle, and a check if `checked`.
struct PickRow: View {
    var title: String
    var subtitle: String?
    var color: String?
    var checked = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let color {
                    Circle().fill(Color(hex: color)).frame(width: 12, height: 12)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.primary).lineLimit(2)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if checked {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(Theme.blue)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

/// A grid of pin colors to pick from.
struct ColorSwatches: View {
    @Binding var value: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
            ForEach(pinColors, id: \.self) { color in
                let selected = color.lowercased() == value.lowercased()
                Button { value = color } label: {
                    Circle()
                        .fill(Color(hex: color))
                        .frame(width: 34, height: 34)
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark").font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay { Circle().stroke(selected ? Theme.tertiaryText : .clear, lineWidth: 3) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color \(color)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
    }
}

/// Where the Space map was last left, so it opens near the user even before there's a location fix,
/// and so searches elsewhere prefer nearby places.
enum MapRegionStore {
    private static let key = "spacetime.space.region.v1"

    static func load() -> SearchRegion? {
        FileStorage.shared.decode(SearchRegion.self, forKey: key)
    }

    static func save(_ region: SearchRegion) {
        FileStorage.shared.encode(region, forKey: key)
    }
}
