//
//  ConnectionViewModel.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class ConnectionViewModel {
    var savedConnections: [SavedConnection] = []
    var isLoading = false
    var errorMessage: String?
    
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
        } catch {
            errorMessage = "Error cargando conexiones: \(error.localizedDescription)"
        }
    }
    
    func connect(using connection: SavedConnection) async {
        print("🔧 ConnectionViewModel.connect(using) SSH: enabled=\(connection.sshEnabled) host=\(connection.sshHost) port=\(connection.sshPort) user=\(connection.sshUsername) passLen=\(connection.sshPassword.count) keyPath=\(connection.sshKeyPath) keyLen=\(connection.sshPrivateKey.count)")
        let req = connection.toConnectRequest()
        await performConnect(
            engine: req.engine, host: req.host, port: req.port,
            username: req.username, password: req.password,
            sslMode: req.sslMode ?? "disable", database: nil, filePath: nil,
            sshEnabled: connection.sshEnabled, sshHost: connection.sshHost,
            sshPort: connection.sshPort, sshUsername: connection.sshUsername,
            sshPassword: connection.sshPassword, sshPrivateKey: connection.sshPrivateKey,
            sshKeyPath: connection.sshKeyPath
        )
        if errorMessage == nil {
            try? databaseManager.markAsUsed(connection)
        }
    }

    func connect(engine: EngineType, host: String, port: Int, username: String, password: String, sslMode: String, filePath: String?, sshEnabled: Bool = false, sshHost: String = "", sshPort: Int = 22, sshUsername: String = "", sshPassword: String = "", sshPrivateKey: String = "", sshKeyPath: String = "") async {
        print("🔧 ConnectionViewModel.connect (direct) SSH: enabled=\(sshEnabled) host=\(sshHost) port=\(sshPort) user=\(sshUsername) passLen=\(sshPassword.count) keyPath=\(sshKeyPath) keyLen=\(sshPrivateKey.count)")
        await performConnect(
            engine: engine, host: host, port: port,
            username: username, password: password,
            sslMode: sslMode, database: nil, filePath: filePath,
            sshEnabled: sshEnabled, sshHost: sshHost, sshPort: sshPort,
            sshUsername: sshUsername, sshPassword: sshPassword,
            sshPrivateKey: sshPrivateKey, sshKeyPath: sshKeyPath
        )
    }
    
    func saveConnection(_ connection: SavedConnection) {
        do {
            try databaseManager.saveConnection(connection)
            loadSavedConnections()
        } catch {
            errorMessage = "Error guardando: \(error.localizedDescription)"
        }
    }
    
    func deleteConnection(_ connection: SavedConnection) {
        do {
            try databaseManager.deleteConnection(connection)
            loadSavedConnections()
        } catch {
            errorMessage = "Error eliminando: \(error.localizedDescription)"
        }
    }
    
    func editConnection(_ connection: SavedConnection) {
        do {
            try databaseManager.updateConnection(connection)
            loadSavedConnections()
        } catch {
            errorMessage = "Error actualizando: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Private
    
    private func performConnect(engine: EngineType, host: String, port: Int, username: String, password: String, sslMode: String, database: String?, filePath: String?, sshEnabled: Bool = false, sshHost: String = "", sshPort: Int = 22, sshUsername: String = "", sshPassword: String = "", sshPrivateKey: String = "", sshKeyPath: String = "") async {
        print("🔧 ConnectionViewModel.performConnect SSH: enabled=\(sshEnabled) host=\(sshHost) port=\(sshPort) user=\(sshUsername) passLen=\(sshPassword.count) keyPath=\(sshKeyPath) keyLen=\(sshPrivateKey.count)")
        isLoading = true
        errorMessage = nil

        if !coreManager.isEngineRunning {
            coreManager.startEngine()
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard let enginePort = coreManager.currentPort else {
            isLoading = false
            errorMessage = "El motor Go no está disponible"
            return
        }

        databaseService.setBaseURL(port: enginePort)

        do {
            try await databaseService.connect(
                engine: engine, host: host, port: port,
                username: username, password: password,
                sslMode: sslMode, database: database, filePath: filePath,
                sshEnabled: sshEnabled, sshHost: sshHost, sshPort: sshPort,
                sshUsername: sshUsername, sshPassword: sshPassword,
                sshPrivateKey: sshPrivateKey, sshKeyPath: sshKeyPath
            )
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Error inesperado: \(error.localizedDescription)"
        }

        isLoading = false
    }
}
