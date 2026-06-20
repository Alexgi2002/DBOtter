//
//  DatabaseModels.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

// MARK: - Table

struct TableEntity: Codable, Identifiable, Hashable {
    let name: String
    let columns: [String]?
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case columns
    }
}

// MARK: - Query Result

struct QueryResult: Codable {
    let columns: [String]
    let rows: [[JSONValue]]
    let isSelect: Bool
    let rowsAffected: Int64?
    let lastInsertID: Int64?
    let message: String?
    let executionMs: Int64?
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        columns = (try? container.decode([String].self, forKey: .columns)) ?? []
        rows = (try? container.decode([[JSONValue]].self, forKey: .rows)) ?? []
        isSelect = (try? container.decode(Bool.self, forKey: .isSelect)) ?? true
        rowsAffected = try? container.decode(Int64.self, forKey: .rowsAffected)
        lastInsertID = try? container.decode(Int64.self, forKey: .lastInsertID)
        message = try? container.decode(String.self, forKey: .message)
        executionMs = try? container.decode(Int64.self, forKey: .executionMs)
    }
    
    init(columns: [String] = [], rows: [[JSONValue]] = [], isSelect: Bool = true, rowsAffected: Int64? = nil, lastInsertID: Int64? = nil, message: String? = nil, executionMs: Int64? = nil) {
        self.columns = columns
        self.rows = rows
        self.isSelect = isSelect
        self.rowsAffected = rowsAffected
        self.lastInsertID = lastInsertID
        self.message = message
        self.executionMs = executionMs
    }
    
    enum CodingKeys: String, CodingKey {
        case columns
        case rows
        case isSelect = "is_select"
        case rowsAffected = "rows_affected"
        case lastInsertID = "last_insert_id"
        case message
        case executionMs = "execution_ms"
    }
}

// MARK: - JSONValue (type-erased for heterogeneous rows)

enum JSONValue: Codable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else {
            self = .null
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
    
    var displayString: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(format: "%.2f", v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return "NULL"
        }
    }
    
    var typeName: String {
        switch self {
        case .string: return "text"
        case .int: return "integer"
        case .double: return "numeric"
        case .bool: return "boolean"
        case .null: return "null"
        }
    }
}

// MARK: - Table Structure (Detailed Metadata)

//struct TableStructure: Codable, Identifiable {
//    let name: String
//    let columns: [ColumnInfo]
//    let indexes: [IndexInfo]
//    let foreignKeys: [ForeignKeyInfo]
//    
//    var id: String { name }
//}

struct ColumnInfo: Codable, Identifiable, Hashable {
    let name: String
    let type: String
    let nullable: Bool
    let defaultValue: String?
    let isPrimaryKey: Bool
    let isForeignKey: Bool
    let refTable: String?
    let refColumn: String?
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case type
        case nullable
        case defaultValue = "default_value"
        case isPrimaryKey = "is_primary_key"
        case isForeignKey = "is_foreign_key"
        case refTable = "ref_table"
        case refColumn = "ref_column"
    }
    
    var typeIcon: String {
        let t = type.lowercased()
        switch true {
        case t.contains("int"): return "number"
        case t.contains("char") || t.contains("text"): return "textformat"
        case t.contains("bool"): return "checkmark.circle"
        case t.contains("date") || t.contains("time"): return "calendar"
        case t.contains("json"): return "curlybraces"
        case t.contains("uuid"): return "key"
        case t.contains("numeric") || t.contains("decimal") || t.contains("float"): return "percent"
        default: return "circle"
        }
    }
    
    var isPrimary: Bool { isPrimaryKey }
    var isFK: Bool { isForeignKey }
}

struct IndexInfo: Codable, Identifiable, Hashable {
    let name: String
    let columns: [String]
    let unique: Bool
    let primary: Bool
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case columns
        case unique
        case primary
    }
}

struct ForeignKeyInfo: Codable, Identifiable, Hashable {
    let name: String
    let column: String
    let refTable: String
    let refColumn: String
    let onUpdate: String
    let onDelete: String
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case column
        case refTable = "ref_table"
        case refColumn = "ref_column"
        case onUpdate = "on_update"
        case onDelete = "on_delete"
    }
}

// MARK: - Response Wrappers

struct Tables: Codable {
    let tables: [TableEntity]
}

struct TableData: Codable {
    let columns: [String]
    let rows: [[JSONValue]]
}

struct TableStructure: Codable {
    let name: String
    let columns: [ColumnInfo]
    let indexes: [IndexInfo]
    let foreignKeys: [ForeignKeyInfo]
}
