//
//  SidebarViewModel.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation
import Combine

@MainActor
@Observable
final class SidebarViewModel {
    
    var savedConnections: [SavedConnection] = []
    var expandedConnections: Set<UUID> = []
    var connectionLoadingStates: [UUID: Bool] = [:]
    var connectionErrors: [UUID: String] = [:]
    
    // Databases per connection
    var connectionDatabases: [UUID: [DatabaseInfo]] = [:]
    var expandedDatabases: [UUID: Set<String>] = [:]
    var databaseLoadingStates: [UUID: Set<String>] = [:]
    var databaseErrors: [UUID: [String: String]] = [:]
    
    // Tables per database (key: "connectionID::dbName")
    var databaseTables: [String: [TableEntity]] = [:]
    
    var selectedTable: String? = nil
    var selectedConnectionId: UUID? = nil
    var searchText: String = ""

    var onReconnected: ((UUID) -> Void)?
    
    // MARK: - Dependencies
    
    private let databaseService = DatabaseService.shared
    private let databaseManager = DatabaseManager.shared
    private let coreManager = CoreManager.shared
    
    // MARK: - Init
    
    init() {
        loadSavedConnections()
    }
    
    // MARK: - Public Methods
    
    func loadSavedConnections() {
        do {
            savedConnections = try databaseManager.fetchConnections()
//            if let first = savedConnections.first, expandedConnections.isEmpty {
//                expandedConnections.insert(first.id)
//            }
        } catch {
            print("Error cargando conexiones: \(error)")
        }
    }
    
    // MARK: - Connection Expansion
    
    func toggleConnectionExpansion(_ connection: SavedConnection) {
        if expandedConnections.contains(connection.id) {
            expandedConnections.remove(connection.id)
        } else {
            expandedConnections.insert(connection.id)
            if connectionDatabases[connection.id] == nil {
                Task { await loadDatabases(for: connection) }
            }
        }
    }
    
    func refreshConnection(_ connection: SavedConnection) async {
        connectionDatabases[connection.id] = nil
        expandedDatabases[connection.id] = nil
        databaseLoadingStates[connection.id] = nil
        databaseErrors[connection.id] = nil
        databaseTables.keys.filter { $0.hasPrefix("\(connection.id)::") }.forEach {
            databaseTables.removeValue(forKey: $0)
        }
        await loadDatabases(for: connection)
    }
    
    func loadDatabases(for connection: SavedConnection) async {
        guard connectionDatabases[connection.id] == nil,
              connectionLoadingStates[connection.id] != true else { return }
        
        connectionLoadingStates[connection.id] = true
        connectionErrors[connection.id] = nil
        
        do {
            try await ensureEngineRunning()
            
            let req = connection.toConnectRequest()
            print("🔧 SidebarViewModel.loadDatabases SSH: enabled=\(connection.sshEnabled) host=\(connection.sshHost) port=\(connection.sshPort) user=\(connection.sshUsername) passLen=\(connection.sshPassword.count) keyPath=\(connection.sshKeyPath) keyLen=\(connection.sshPrivateKey.count)")
            
            try await databaseService.connect(
                engine: req.engine, host: req.host, port: req.port,
                username: req.username, password: req.password,
                sslMode: req.sslMode ?? "disable", database: nil, filePath: nil,
                sshEnabled: connection.sshEnabled,
                sshHost: connection.sshHost,
                sshPort: connection.sshPort,
                sshUsername: connection.sshUsername,
                sshPassword: connection.sshPassword,
                sshPrivateKey: connection.sshPrivateKey,
                sshKeyPath: connection.sshKeyPath
            )
            
            let databases = try await databaseService.fetchDatabases()
            connectionDatabases[connection.id] = databases
            try databaseManager.markAsUsed(connection)
            loadSavedConnections()
            onReconnected?(connection.id)
            
        } catch let error as APIError {
            connectionErrors[connection.id] = error.errorDescription
        } catch {
            connectionErrors[connection.id] = "Error: \(error.localizedDescription)"
        }
        
        connectionLoadingStates[connection.id] = false
    }
    
    // MARK: - Database Expansion
    
    func toggleDatabaseExpansion(_ dbName: String, for connection: SavedConnection) {
        let key = databaseTablesKey(connectionId: connection.id, dbName: dbName)
        
        if expandedDatabases[connection.id]?.contains(dbName) == true {
            expandedDatabases[connection.id]?.remove(dbName)
        } else {
            if expandedDatabases[connection.id] == nil {
                expandedDatabases[connection.id] = []
            }
            expandedDatabases[connection.id]?.insert(dbName)
            
            if databaseTables[key] == nil {
                Task { await loadTables(for: dbName, in: connection) }
            }
        }
    }
    
    func loadTables(for dbName: String, in connection: SavedConnection) async {
        let key = databaseTablesKey(connectionId: connection.id, dbName: dbName)
        
        if databaseLoadingStates[connection.id] == nil {
            databaseLoadingStates[connection.id] = []
        }
        guard !databaseLoadingStates[connection.id]!.contains(dbName) else { return }
        databaseLoadingStates[connection.id]!.insert(dbName)
        
        if databaseErrors[connection.id] == nil {
            databaseErrors[connection.id] = [:]
        }
        databaseErrors[connection.id]![dbName] = nil
        
        do {
            try await ensureEngineRunning()
            
            // Reconnect to the specific database
            let req = connection.toConnectRequest(database: dbName)
            print("🔧 SidebarViewModel.loadTables SSH: enabled=\(connection.sshEnabled) host=\(connection.sshHost) port=\(connection.sshPort) user=\(connection.sshUsername) passLen=\(connection.sshPassword.count) keyPath=\(connection.sshKeyPath) keyLen=\(connection.sshPrivateKey.count)")
            
            try await databaseService.connect(
                engine: req.engine, host: req.host, port: req.port,
                username: req.username, password: req.password,
                sslMode: req.sslMode ?? "disable",
                database: dbName, filePath: nil,
                sshEnabled: connection.sshEnabled,
                sshHost: connection.sshHost,
                sshPort: connection.sshPort,
                sshUsername: connection.sshUsername,
                sshPassword: connection.sshPassword,
                sshPrivateKey: connection.sshPrivateKey,
                sshKeyPath: connection.sshKeyPath
            )
            
            let tables = try await databaseService.fetchTables(schema: "public")
            databaseTables[key] = tables
            
        } catch let error as APIError {
            databaseErrors[connection.id]![dbName] = error.errorDescription
        } catch {
            databaseErrors[connection.id]![dbName] = "Error: \(error.localizedDescription)"
        }
        
        databaseLoadingStates[connection.id]?.remove(dbName)
    }
    
    // MARK: - Selection
    
    func selectTable(_ tableName: String, from connection: SavedConnection) {
        selectedTable = tableName
        selectedConnectionId = connection.id
    }
    
    // MARK: - CRUD
    
    func deleteConnection(_ connection: SavedConnection) {
        do {
            try databaseManager.deleteConnection(connection)
            connectionDatabases.removeValue(forKey: connection.id)
            expandedDatabases.removeValue(forKey: connection.id)
            connectionLoadingStates.removeValue(forKey: connection.id)
            connectionErrors.removeValue(forKey: connection.id)
            databaseLoadingStates.removeValue(forKey: connection.id)
            databaseErrors.removeValue(forKey: connection.id)
            databaseTables.keys.filter { $0.hasPrefix("\(connection.id)::") }.forEach {
                databaseTables.removeValue(forKey: $0)
            }
            expandedConnections.remove(connection.id)
            loadSavedConnections()
        } catch {
            print("Error eliminando conexión: \(error)")
        }
    }
    
    func addConnection(_ connection: SavedConnection) {
        do {
            try databaseManager.saveConnection(connection)
            loadSavedConnections()
        } catch {
            print("Error guardando conexión: \(error)")
        }
    }
    
    func editConnection(_ connection: SavedConnection) {
        do {
            try databaseManager.updateConnection(connection)
            loadSavedConnections()
        } catch {
            print("Error actualizando conexión: \(error)")
        }
    }
    
    // MARK: - Computed
    
    func databases(for connection: SavedConnection) -> [DatabaseInfo] {
        connectionDatabases[connection.id] ?? []
    }
    
    func tables(for dbName: String, in connection: SavedConnection) -> [TableEntity] {
        let key = databaseTablesKey(connectionId: connection.id, dbName: dbName)
        return databaseTables[key] ?? []
    }
    
    func isConnectionExpanded(_ connection: SavedConnection) -> Bool {
        expandedConnections.contains(connection.id)
    }
    
    func isConnectionLoading(_ connection: SavedConnection) -> Bool {
        connectionLoadingStates[connection.id] ?? false
    }
    
    func connectionError(_ connection: SavedConnection) -> String? {
        connectionErrors[connection.id]
    }
    
    func isDatabaseExpanded(_ dbName: String, for connection: SavedConnection) -> Bool {
        expandedDatabases[connection.id]?.contains(dbName) == true
    }
    
    func isDatabaseLoading(_ dbName: String, for connection: SavedConnection) -> Bool {
        databaseLoadingStates[connection.id]?.contains(dbName) == true
    }
    
    func databaseError(_ dbName: String, for connection: SavedConnection) -> String? {
        databaseErrors[connection.id]?[dbName]
    }
    
    // MARK: - Private
    
    private func ensureEngineRunning() async throws {
        if !coreManager.isEngineRunning {
            coreManager.startEngine()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        guard let port = coreManager.currentPort else {
            throw APIError.serverError("Motor Go no disponible")
        }
        databaseService.setBaseURL(port: port)
    }
    
    private func databaseTablesKey(connectionId: UUID, dbName: String) -> String {
        "\(connectionId.uuidString)::\(dbName)"
    }
}
