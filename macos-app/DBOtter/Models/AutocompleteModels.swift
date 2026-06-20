//
//  AutocompleteModels.swift
//  DBOtter
//
//  Created by AlexGI on 14/06/2026.
//

import Foundation

// MARK: - Suggestion Type

enum SuggestionType: String, Codable, Hashable {
    case keyword
    case table
    case column
    case function
    case schema
    
    var displayName: String {
        switch self {
        case .keyword: return "Keyword"
        case .table: return "Table"
        case .column: return "Column"
        case .function: return "Function"
        case .schema: return "Schema"
        }
    }
    
    var iconName: String {
        switch self {
        case .keyword: return "text.word.spacing"
        case .table: return "tablecells"
        case .column: return "column"
        case .function: return "function"
        case .schema: return "folder"
        }
    }
}

// MARK: - Autocomplete Suggestion

struct AutocompleteSuggestion: Identifiable, Hashable {
    let text: String           // What gets inserted
    let displayText: String    // What's shown in popup
    let type: SuggestionType   // keyword, table, column, function
    let detail: String?        // Extra info (e.g., column type)
    
    var id: String { "\(text)-\(type.rawValue)" }
}

// MARK: - Trigger Type

enum TriggerType: Hashable {
    case prefix(String)        // User typed some characters
    case dot(table: String)    // User typed "table."
    case none                  // No trigger
}

// MARK: - Editor Context

struct EditorContext {
    let textBeforeCursor: String
    let currentWord: String
    let isAfterDot: Bool
    let tableBeforeDot: String?
    let triggerType: TriggerType
}

// MARK: - Schema Data (for caching)

struct SchemaData {
    let tableNames: [String]
    let columnsByTable: [String: [ColumnInfo]]
    let lastUpdated: Date
    
    var estimatedSize: Int {
        // Rough estimate: 50 bytes per table name + 100 bytes per column
        let tableSize = tableNames.count * 50
        let columnSize = columnsByTable.values.reduce(0) { $0 + $1.count * 100 }
        return tableSize + columnSize
    }
}