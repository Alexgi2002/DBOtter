import SwiftUI

struct SQLAutocompletePopover: View {
    var viewModel: CodeEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.showingSuggestions && !viewModel.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion) {
                            viewModel.insertSuggestion(suggestion)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .shadow(radius: 2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SuggestionRow: View {
    let suggestion: AutocompleteSuggestion
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForType(suggestion.type))
                .font(.caption)
                .foregroundColor(.secondary)

            Text(suggestion.displayText)
                .font(.caption)

            if let detail = suggestion.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(2)
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { isHovered = $0 }
        #endif
        .onTapGesture { onTap() }
    }

    private func iconForType(_ type: SuggestionType) -> String {
        switch type {
        case .keyword:  return "chevron.left.forwardslash.chevron.right"
        case .table:    return "tablecells"
        case .column:   return "ellipsis"
        case .function: return "function"
        case .schema:   return "folder"
        }
    }
}
