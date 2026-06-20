//
//  SchemaCache.swift
//  DBOtter
//
//  Created by AlexGI on 14/06/2026.
//

import Foundation

@MainActor
final class SchemaCache {
    static let shared = SchemaCache()
    
    private(set) var tableNames: [String] = []
    private(set) var columnsByTable: [String: [ColumnInfo]] = [:]
    
    private var lastUpdated: Date?
    private let ttl: TimeInterval = 5 * 60 // 5 minutes
    private let maxSize: Int = 100 * 1024 // 100KB
    
    private let databaseService = DatabaseService.shared
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Load schema data if needed (cache miss or expired)
    func loadIfNeeded() async throws {
        guard !isCacheValid() else {
            return
        }
        try await refresh()
    }
    
    /// Check if cache has been loaded and has data
    func hasData() -> Bool {
        return !tableNames.isEmpty
    }
    
    /// Force refresh schema data from backend
    func refresh() async throws {
        // Fetch all tables (uses default schema "public")
        let tables = try await databaseService.fetchTables(schema: "public")
        let tableNames = tables.map { $0.name }
        
        // Fetch columns for each table (limit to first 50 tables for performance)
        var columnsByTable: [String: [ColumnInfo]] = [:]
        let tablesToFetch = Array(tableNames.prefix(50))
        
        for tableName in tablesToFetch {
            let structure = try await databaseService.fetchTableStructure(table: tableName, schema: "public")
            columnsByTable[tableName] = structure.columns
        }
        
        // Update cache
        self.tableNames = tableNames
        self.columnsByTable = columnsByTable
        self.lastUpdated = Date()
        
        // Check size limit
        let estimatedSize = SchemaData(
            tableNames: tableNames,
            columnsByTable: columnsByTable,
            lastUpdated: Date()
        ).estimatedSize
        
        if estimatedSize > maxSize {
            print("⚠️ SchemaCache: Cache size (\(estimatedSize) bytes) exceeds limit (\(maxSize) bytes)")
        }
    }
    
    /// Clear all cached data
    func clear() {
        tableNames = []
        columnsByTable = [:]
        lastUpdated = nil
    }
    
    /// Get column names for a specific table
    func columns(for table: String) -> [String] {
        columnsByTable[table]?.map { $0.name } ?? []
    }
    
    // MARK: - Private Methods
    
    private func isCacheValid() -> Bool {
        guard let lastUpdated = lastUpdated else {
            return false
        }
        return Date().timeIntervalSince(lastUpdated) < ttl
    }
}
