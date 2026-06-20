//
//  PersistedTab.swift
//  DBOtter

import Foundation
import SwiftData

@Model
final class PersistedTab {
    var id: UUID
    var tableName: String
    var connectionId: UUID
    var dbName: String
    var connectionName: String
    var sortOrder: Int
    var isActive: Bool

    init(id: UUID = UUID(), tableName: String, connectionId: UUID, dbName: String, connectionName: String, sortOrder: Int, isActive: Bool = false) {
        self.id = id
        self.tableName = tableName
        self.connectionId = connectionId
        self.dbName = dbName
        self.connectionName = connectionName
        self.sortOrder = sortOrder
        self.isActive = isActive
    }
}
