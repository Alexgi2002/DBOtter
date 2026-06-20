//
//  DatabaseManager.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation
import SwiftData

@MainActor
final class DatabaseManager {
    static let shared = DatabaseManager()
    
    let container: ModelContainer
    let context: ModelContext
    
    private init() {
        // Use the shared container from the app
        self.container = DBOtterApp.sharedModelContainer
        self.context = ModelContext(container)
        context.autosaveEnabled = true
    }
    
    // MARK: - SavedConnection Operations
    
    func fetchConnections() throws -> [SavedConnection] {
        let descriptor = FetchDescriptor<SavedConnection>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse), SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }
    
    func fetchConnection(id: UUID) throws -> SavedConnection? {
        let descriptor = FetchDescriptor<SavedConnection>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }
    
    func saveConnection(_ connection: SavedConnection) throws {
        context.insert(connection)
        try context.save()
    }
    
    func updateConnection(_ connection: SavedConnection) throws {
        connection.updatedAt = Date()
        try context.save()
    }
    
    func deleteConnection(_ connection: SavedConnection) throws {
        context.delete(connection)
        try context.save()
    }
    
    func deleteConnection(id: UUID) throws {
        if let connection = try fetchConnection(id: id) {
            try deleteConnection(connection)
        }
    }
    
    func markAsUsed(_ connection: SavedConnection) throws {
        connection.updateLastUsed()
        try context.save()
    }
    
    // MARK: - PersistedTab Operations
    
    func fetchTabs() throws -> [PersistedTab] {
        let descriptor = FetchDescriptor<PersistedTab>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return try context.fetch(descriptor)
    }
    
    func saveTab(_ tab: PersistedTab) throws {
        context.insert(tab)
        try context.save()
    }
    
    func deleteTab(_ tab: PersistedTab) throws {
        context.delete(tab)
        try context.save()
    }
    
    func deleteAllTabs() throws {
        let tabs = try fetchTabs()
        tabs.forEach { context.delete($0) }
        try context.save()
    }
    
    func saveTabs(snapshot: [(tab: TableTab, order: Int, isActive: Bool)]) throws {
        let existing = try fetchTabs()
        existing.forEach { context.delete($0) }
        for item in snapshot {
            let p = PersistedTab(
                id: item.tab.id,
                tableName: item.tab.tableName,
                connectionId: item.tab.connectionId,
                dbName: item.tab.dbName,
                connectionName: item.tab.connectionName,
                sortOrder: item.order,
                isActive: item.isActive
            )
            context.insert(p)
        }
        try context.save()
    }
}
