import Foundation
import SwiftUI

@MainActor
@Observable
final class CodeEditorViewModel {
    var text: String = ""
    var suggestions: [AutocompleteSuggestion] = []
    var showingSuggestions: Bool = false
    var isSchemaLoading: Bool = false
    var schemaError: String? = nil
    var selectedIndex: Int = 0
    private let schemaCache = SchemaCache.shared
    
    func analyzeContext(beforeCursor: String, currentWord: String, isAfterDot: Bool, tableBeforeDot: String?) -> EditorContext {
        var triggerType: TriggerType
        
        if isAfterDot && tableBeforeDot != nil {
            triggerType = .dot(table: tableBeforeDot!)
        } else if !currentWord.isEmpty {
            triggerType = .prefix(currentWord)
        } else {
            triggerType = .none
        }
        
        return EditorContext(
            textBeforeCursor: beforeCursor,
            currentWord: currentWord,
            isAfterDot: isAfterDot,
            tableBeforeDot: tableBeforeDot,
            triggerType: triggerType
        )
    }
    
    func filterSuggestions(context: EditorContext) -> [AutocompleteSuggestion] {
        var suggestions: [AutocompleteSuggestion] = []
        
        // Handle empty schema (no tables cached)
        if schemaCache.tableNames.isEmpty {
            return []
        }
        
        if context.currentWord.count >= 2 {
            if context.isAfterDot {
                // Handle multiple dots and column suggestions
                let parts = context.textBeforeCursor.split(separator: ".").compactMap { $0.trimmingCharacters(in: .whitespaces) }
                
                if let lastTable = parts.last, !lastTable.isEmpty {
                    // Column suggestions for the last table
                    if let columns = schemaCache.columnsByTable[lastTable] {
                        suggestions = columns.filter { $0.name.hasPrefix(context.currentWord) }
                            .map { AutocompleteSuggestion(
                                text: $0.name,
                                displayText: $0.name,
                                type: .column,
                                detail: $0.type
                            ) }
                    }
                    // If no columns found for the last table, try table suggestions as fallback
                    else if suggestions.isEmpty && parts.count > 1 {
                        let previousTable = parts[parts.count - 2]
                        if let columns = schemaCache.columnsByTable[previousTable] {
                            suggestions = columns.filter { $0.name.hasPrefix(context.currentWord) }
                                .map { AutocompleteSuggestion(
                                    text: $0.name,
                                    displayText: $0.name,
                                    type: .column,
                                    detail: $0.type
                                ) }
                        }
                    }
                }
            } else {
                // Table suggestions - handle schemas with dot notation
                let tables = schemaCache.tableNames.filter { tableName in
                    if context.textBeforeCursor.contains(".") {
                        // User is typing schema.table format
                        let parts = context.textBeforeCursor.split(separator: ".").compactMap { $0.trimmingCharacters(in: .whitespaces) }
                        if parts.count >= 2 {
                            // For nested dot, only match tables that start with current word
                            return tableName.hasPrefix(context.currentWord)
                        }
                    }
                    return tableName.hasPrefix(context.currentWord)
                }
                
                suggestions = tables.map { AutocompleteSuggestion(
                    text: $0,
                    displayText: $0,
                    type: .table,
                    detail: nil
                ) }
            }
        }
        
        return suggestions
    }
    
    func insertSuggestion(_ suggestion: AutocompleteSuggestion) {
        // Enhanced text insertion with proper dot handling
        let textBeforeCursor = text
        let parts = textBeforeCursor.split(separator: ".").compactMap { $0.trimmingCharacters(in: .whitespaces) }
        
        if parts.count == 0 {
            // No dots, just insert
            text = suggestion.text + " "
        } else if parts.count == 1 && parts[0] == "" {
            // Only dots (e.g., "." at start)
            text = ". " + suggestion.text + " "
        } else {
            // Has dots, complete the last segment
            let lastPart = parts.last ?? ""
            if lastPart.isEmpty {
                // Last part is empty, just add a dot and the suggestion
                text = textBeforeCursor + ". " + suggestion.text + " "
            } else {
                // Replace the last part with the suggestion
                var newText = ""
                for (index, part) in parts.enumerated() {
                    if index > 0 {
                        newText += "."
                    }
                    if index == parts.count - 1 {
                        newText += suggestion.text
                    } else {
                        newText += part
                    }
                }
                text = newText + " "
            }
        }
        showingSuggestions = false
        suggestions = []
    }
    
    func handleKeyboardShortcut(key: Character, modifiers: EventModifiers) {
        if modifiers.contains(.command) && key == "\r" {
            // Cmd+Enter handled by parent view via .keyboardShortcut
        } else if key == "\u{001B}" {
            showingSuggestions = false
            suggestions = []
        } else if key == "\t" && showingSuggestions {
            if !suggestions.isEmpty && selectedIndex < suggestions.count {
                insertSuggestion(suggestions[selectedIndex])
            }
        }
    }
}
