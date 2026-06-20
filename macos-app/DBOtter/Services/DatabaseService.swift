//
//  DatabaseService.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

@MainActor
final class DatabaseService {
    static let shared = DatabaseService()
    
    private let apiClient = APIClient.shared
    private var baseURL: URL?
    
    private init() {}
    
    // MARK: - Configuration
    
    func setBaseURL(port: Int) {
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")
    }
    
    var isConfigured: Bool {
        baseURL != nil
    }
    
    // MARK: - Connection
    
    func connect(engine: EngineType, host: String, port: Int, username: String, password: String, sslMode: String, database: String?, filePath: String?, sshEnabled: Bool = false, sshHost: String = "", sshPort: Int = 22, sshUsername: String = "", sshPassword: String = "", sshPrivateKey: String = "", sshKeyPath: String = "") async throws {
        guard let baseURL = baseURL else { throw APIError.invalidURL }

        print("🔧 DatabaseService.connect SSH params: enabled=\(sshEnabled) host=\(sshHost) port=\(sshPort) user=\(sshUsername) passLen=\(sshPassword.count) keyPath=\(sshKeyPath) keyLen=\(sshPrivateKey.count)")

        let request = ConnectRequest(
            engine: engine,
            host: host,
            port: port,
            username: username,
            password: password,
            sslMode: sslMode,
            database: database,
            filePath: filePath,
            sshEnabled: sshEnabled ? true : nil,
            sshHost: sshEnabled && !sshHost.isEmpty ? sshHost : nil,
            sshPort: sshEnabled ? sshPort : nil,
            sshUsername: sshEnabled && !sshUsername.isEmpty ? sshUsername : nil,
            sshPassword: sshEnabled && !sshPassword.isEmpty ? sshPassword : nil,
            sshPrivateKey: sshEnabled && !sshPrivateKey.isEmpty ? sshPrivateKey : nil,
            sshKeyPath: sshEnabled && !sshKeyPath.isEmpty ? sshKeyPath : nil
        )
        
        // Debug: print JSON being sent
        if let jsonData = try? JSONEncoder().encode(request),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            print("📤 ConnectRequest JSON: \(jsonString)")
        }
        
        let endpoint = ConnectEndpoint(baseURL: baseURL, request: request)
        let _: ConnectResponse = try await apiClient.request(endpoint)
    }
    
    // MARK: - Databases
    
    func fetchDatabases() async throws -> [DatabaseInfo] {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }
        
        let endpoint = GetDatabasesEndpoint(baseURL: baseURL)
        let response: DatabasesResponse = try await apiClient.request(endpoint)
        return response.databases
    }
    
    // MARK: - Tables
    
    func fetchTables(schema: String = "public") async throws -> [TableEntity] {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }
        
        let endpoint = GetTablesEndpoint(baseURL: baseURL, schema: schema)
        let response: TablesResponse = try await apiClient.request(endpoint)
        return response.tables
    }
    
    // MARK: - Table Data
    
    func fetchTableData(table: String, limit: Int = 100, offset: Int = 0) async throws -> QueryResult {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }
        
        let endpoint = GetTableDataEndpoint(baseURL: baseURL, table: table, limit: limit, offset: offset)
        let response: TableDataResponse = try await apiClient.request(endpoint)
        
        return QueryResult(columns: response.columns, rows: response.rows)
    }
    
    // MARK: - Query Execution
    
    func executeQuery(_ query: String) async throws -> QueryResult {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }
        
        let endpoint = ExecuteQueryEndpoint(baseURL: baseURL, query: query)
        let response: QueryResult = try await apiClient.request(endpoint)
        return response
    }
    
    // MARK: - Export
    
    func exportTable(_ options: ExportOptions) async throws -> Data {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }
        
        let endpoint = ExportEndpoint(baseURL: baseURL, options: options)
        let request = try endpoint.makeRequest()
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return data
    }
    
    // MARK: - Table Structure
    
    func fetchTableStructure(table: String, schema: String = "public") async throws -> TableStructure {
        guard let baseURL = baseURL else {
            throw APIError.invalidURL
        }
        
        let endpoint = GetTableStructureEndpoint(baseURL: baseURL, table: table, schema: schema)
        let response: TableStructureResponse = try await apiClient.request(endpoint)
        
        return TableStructure(
            name: response.name,
            columns: response.columns,
            indexes: response.indexes,
            foreignKeys: response.foreignKeys
        )
    }
    
    // MARK: - Schema Data for Autocompletion
    
    /// Fetch all schema data (table names + columns for each table) in a single batch
    /// Returns a tuple with table names and columns grouped by table name
    func fetchAllSchemaData() async throws -> (tableNames: [String], columnsByTable: [String: [ColumnInfo]]) {
        // Fetch all tables
        let tables = try await fetchTables()
        let tableNames = tables.map { $0.name }
        
        // Fetch columns for each table
        var columnsByTable: [String: [ColumnInfo]] = [:]
        
        // Use TaskGroup for concurrent fetching (limited concurrency)
        try await withThrowingTaskGroup(of: (String, [ColumnInfo]).self) { group in
            for table in tableNames {
                group.addTask { [weak self] in
                    let structure = try await self?.fetchTableStructure(table: table)
                    return (table, structure?.columns ?? [])
                }
            }
            
            for try await (tableName, columns) in group {
                columnsByTable[tableName] = columns
            }
        }
        
        return (tableNames: tableNames, columnsByTable: columnsByTable)
    }
}
