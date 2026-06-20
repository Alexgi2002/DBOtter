//
//  TableTab.swift
//  DBOtter

import Foundation

struct TableTab: Identifiable, Equatable {
    let id: UUID
    let tableName: String
    let connectionId: UUID
    let dbName: String
    let connectionName: String

    init(tableName: String, connectionId: UUID, dbName: String, connectionName: String) {
        self.id = UUID()
        self.tableName = tableName
        self.connectionId = connectionId
        self.dbName = dbName
        self.connectionName = connectionName
    }

    init(from persisted: PersistedTab) {
        self.id = persisted.id
        self.tableName = persisted.tableName
        self.connectionId = persisted.connectionId
        self.dbName = persisted.dbName
        self.connectionName = persisted.connectionName
    }
}
