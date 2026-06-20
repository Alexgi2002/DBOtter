//
//  GoEndpoints.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

// MARK: - Go Backend Endpoints

struct ConnectEndpoint: Endpoint {
    let baseURL: URL
    let request: ConnectRequest
    
    var path: String { "/connect" }
    var method: HTTPMethod { .POST }
    var body: Encodable? { request }
}

struct GetDatabasesEndpoint: Endpoint {
    let baseURL: URL
    
    var path: String { "/databases" }
    var method: HTTPMethod { .GET }
}

struct GetTablesEndpoint: Endpoint {
    let baseURL: URL
    let schema: String
    
    var path: String { "/tables" }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? {
        [URLQueryItem(name: "schema", value: schema)]
    }
}

struct GetTableDataEndpoint: Endpoint {
    let baseURL: URL
    let table: String
    let limit: Int
    let offset: Int
    
    var path: String { "/table-data" }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? {
        [
            URLQueryItem(name: "table", value: table),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
    }
}

struct ExecuteQueryEndpoint: Endpoint {
    let baseURL: URL
    let query: String
    
    var path: String { "/query" }
    var method: HTTPMethod { .POST }
    var body: Encodable? {
        ["query": query]
    }
}

struct GetTableStructureEndpoint: Endpoint {
    let baseURL: URL
    let table: String
    let schema: String
    
    var path: String { "/table-structure" }
    var method: HTTPMethod { .GET }
    var queryItems: [URLQueryItem]? {
        [
            URLQueryItem(name: "table", value: table),
            URLQueryItem(name: "schema", value: schema)
        ]
    }
}

struct ExportEndpoint: Endpoint {
    let baseURL: URL
    let options: ExportOptions
    
    var path: String { "/export" }
    var method: HTTPMethod { .POST }
    var body: Encodable? { options }
}

// MARK: - Export Options

struct ExportOptions: Codable {
    let tableName: String
    let format: String
    let columns: [String]?
    let limit: Int?
    let offset: Int?
    let search: String?
    let sortBy: String?
    let sortDesc: Bool?
    let whereClause: String?
    let delimiter: String?
    let quoteChar: String?
    let encoding: String?
    let sheetName: String?
    let freezePanes: Bool?
    let autoWidth: Bool?
    let headerBold: Bool?
    let includeHeader: Bool?
    let includeTypes: Bool?
    let includeTimestamp: Bool?
    let includeStats: Bool?
    
    enum CodingKeys: String, CodingKey {
        case tableName = "table_name"
        case format
        case columns
        case limit
        case offset
        case search
        case sortBy = "sort_by"
        case sortDesc = "sort_desc"
        case whereClause = "where"
        case delimiter
        case quoteChar = "quote_char"
        case encoding
        case sheetName = "sheet_name"
        case freezePanes = "freeze_panes"
        case autoWidth = "auto_width"
        case headerBold = "header_bold"
        case includeHeader = "include_header"
        case includeTypes = "include_types"
        case includeTimestamp = "include_timestamp"
        case includeStats = "include_stats"
    }
}

// MARK: - Response Types (matching Go backend)

struct DatabasesResponse: Decodable {
    let databases: [DatabaseInfo]
    
    init(from decoder: Decoder) throws {
        // Go backend devuelve [{...}] directamente
        var container = try decoder.unkeyedContainer()
        var databases: [DatabaseInfo] = []
        while !container.isAtEnd {
            let db = try container.decode(DatabaseInfo.self)
            databases.append(db)
        }
        self.databases = databases
    }
}

struct TablesResponse: Decodable {
    let tables: [TableEntity]
    
    init(from decoder: Decoder) throws {
        // Go backend devuelve [{...}] directamente en vez de {"tables": [{...}]}
        var container = try decoder.unkeyedContainer()
        var tables: [TableEntity] = []
        while !container.isAtEnd {
            let table = try container.decode(TableEntity.self)
            tables.append(table)
        }
        self.tables = tables
    }
}

struct TableDataResponse: Decodable {
    let columns: [String]
    let rows: [[JSONValue]]
}

struct TableStructureResponse: Decodable {
    let name: String
    let columns: [ColumnInfo]
    let indexes: [IndexInfo]
    let foreignKeys: [ForeignKeyInfo]

    enum CodingKeys: String, CodingKey {
        case name
        case columns
        case indexes
        case foreignKeys = "foreign_keys"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.name = try container.decode(String.self, forKey: .name)
        self.columns = try container.decodeIfPresent([ColumnInfo].self, forKey: .columns) ?? []
        self.indexes = try container.decodeIfPresent([IndexInfo].self, forKey: .indexes) ?? []
        self.foreignKeys = try container.decodeIfPresent([ForeignKeyInfo].self, forKey: .foreignKeys) ?? []
    }
}
