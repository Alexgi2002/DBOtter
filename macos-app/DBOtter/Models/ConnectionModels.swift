//
//  ConnectionModels.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Engine Type

enum EngineType: String, Codable, CaseIterable, Identifiable {
    case postgres = "postgres"
    case mysql = "mysql"
    case sqlite = "sqlite"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .postgres: return "PostgreSQL"
        case .mysql:    return "MySQL"
        case .sqlite:   return "SQLite"
        }
    }
    
    var iconName: String {
        switch self {
        case .postgres: return "postgres"
        case .mysql:    return "mysql"
        case .sqlite:   return "sqlite"
        }
    }
    
    var color: Color {
        switch self {
        case .postgres: return .blue
        case .mysql:    return .orange
        case .sqlite:   return .purple
        }
    }

    var defaultPort: Int {
        switch self {
        case .postgres: return 5432
        case .mysql:    return 3306
        case .sqlite:   return 0
        }
    }
    
    var defaultHost: String {
        switch self {
        case .postgres: return "localhost"
        case .mysql:    return "localhost"
        case .sqlite:   return ""
        }
    }
    
    var defaultSSLMode: String {
        switch self {
        case .postgres: return "disable"
        case .mysql:    return "disable"
        case .sqlite:   return ""
        }
    }
    
    var urlScheme: String {
        switch self {
        case .postgres: return "postgresql"
        case .mysql:    return "mysql"
        case .sqlite:   return "sqlite"
        }
    }
    
    var supportsSSL: Bool {
        switch self {
        case .postgres, .mysql: return true
        case .sqlite:           return false
        }
    }
    
    var supportsHostPort: Bool {
        switch self {
        case .postgres, .mysql: return true
        case .sqlite:           return false
        }
    }
    
    var supportsAuth: Bool {
        switch self {
        case .postgres, .mysql: return true
        case .sqlite:           return false
        }
    }
}

// MARK: - Connect Request (envía campos individuales a Go)

struct ConnectRequest: Codable {
    let engine: EngineType
    let host: String
    let port: Int
    let username: String
    let password: String
    let sslMode: String?
    let database: String?
    let filePath: String?
    // SSH Tunnel
    let sshEnabled: Bool?
    let sshHost: String?
    let sshPort: Int?
    let sshUsername: String?
    let sshPassword: String?
    let sshPrivateKey: String?
    let sshKeyPath: String?
}

struct ConnectResponse: Codable {
    let status: String
}

// MARK: - Database Info (respuesta de GET /databases)

struct DatabaseInfo: Codable, Identifiable, Hashable {
    let name: String
    let owner: String?
    let encoding: String?
    let collation: String?
    let description: String?
    let isDefault: Bool?
    
    var id: String { name }
}

// MARK: - Saved Connection (SwiftData Model)

@Model
final class SavedConnection {
    var id: UUID
    var name: String
    var engine: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var sslMode: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    // SSH
    var sshEnabled: Bool
    var sshHost: String
    var sshPort: Int
    var sshUsername: String
    var sshPassword: String
    var sshPrivateKey: String
    var sshKeyPath: String

    init(
        name: String,
        engine: EngineType,
        host: String,
        port: Int,
        username: String,
        password: String,
        sslMode: String,
        sshEnabled: Bool = false,
        sshHost: String = "",
        sshPort: Int = 22,
        sshUsername: String = "",
        sshPassword: String = "",
        sshPrivateKey: String = "",
        sshKeyPath: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.engine = engine.rawValue
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.sslMode = sslMode
        self.createdAt = Date()
        self.updatedAt = Date()
        self.lastUsedAt = nil
        self.sshEnabled = sshEnabled
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUsername = sshUsername
        self.sshPassword = sshPassword
        self.sshPrivateKey = sshPrivateKey
        self.sshKeyPath = sshKeyPath
    }
    
    var engineType: EngineType {
        EngineType(rawValue: engine) ?? .postgres
    }
    
    var displayName: String {
        "\(engineType.displayName) · \(username)@\(host):\(port)"
    }
    
    var summary: String {
        "\(username)@\(host):\(port)"
    }
    
    func toConnectRequest(database: String? = nil) -> ConnectRequest {
        ConnectRequest(
            engine: engineType,
            host: host,
            port: port,
            username: username,
            password: password,
            sslMode: sslMode,
            database: database,
            filePath: nil,
            sshEnabled: sshEnabled ? true : nil,
            sshHost: sshEnabled ? sshHost : nil,
            sshPort: sshEnabled ? sshPort : nil,
            sshUsername: sshEnabled ? sshUsername : nil,
            sshPassword: sshEnabled && !sshPassword.isEmpty ? sshPassword : nil,
            sshPrivateKey: sshEnabled && !sshPrivateKey.isEmpty ? sshPrivateKey : nil,
            sshKeyPath: sshEnabled && !sshKeyPath.isEmpty ? sshKeyPath : nil
        )
    }
    
    func updateLastUsed() {
        lastUsedAt = Date()
        updatedAt = Date()
    }
}
