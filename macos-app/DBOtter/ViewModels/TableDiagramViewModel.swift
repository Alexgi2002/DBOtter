//
//  TableDiagramViewModel.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class TableDiagramViewModel {
    // MARK: - Data
    var tableStructures: [String: TableStructure] = [:]
    var nodePositions: [String: CGPoint] = [:]
    var nodeDragDeltas: [String: CGSize] = [:]
    var isLoading = false
    var errorMessage: String?
    var selectedTable: String?
    var zoom: CGFloat = 1.0
    var panOffset: CGSize = .zero
    var accumulatedPan: CGSize = .zero
    private var lastMagnification: CGFloat = 1.0
    
    // MARK: - Private
    private let databaseService = DatabaseService.shared
    private let taskHolder = TaskHolder()
    private let connectionId: UUID
    
    // MARK: - Init
    
    init(connectionId: UUID) {
        self.connectionId = connectionId
    }
    
    // MARK: - Public Methods
    
    func loadDiagram() async {
        taskHolder.task?.cancel()
        
        taskHolder.task = Task {
            await performLoad()
        }
        
        await taskHolder.task?.value
    }
    
    func refresh() {
        Task { await loadDiagram() }
    }
    
    func selectTable(_ tableName: String) {
        selectedTable = tableName
    }
    
    func updatePosition(_ tableName: String, position: CGPoint) {
        nodePositions[tableName] = position
    }
    
    func resetZoom() {
        zoom = 1.0
        panOffset = .zero
        accumulatedPan = .zero
    }
    
    func zoomIn() {
        zoom = min(zoom * 1.2, 3.0)
    }
    
    func zoomOut() {
        zoom = max(zoom / 1.2, 0.3)
    }
    
    func applyZoom(_ scale: CGFloat) {
        let delta = scale / lastMagnification
        zoom = max(0.3, min(3.0, zoom * delta))
        lastMagnification = scale
    }

    func resetMagnification() {
        lastMagnification = 1.0
    }
    
    func autoLayout() {
        let tables = Array(tableStructures.keys)
        guard !tables.isEmpty else { return }

        // Build dependency graph: table -> set of tables it references (FK targets)
        var deps: [String: Set<String>] = [:]
        for name in tables { deps[name] = [] }
        for (_, structure) in tableStructures {
            for fk in structure.foreignKeys where tableStructures[fk.refTable] != nil {
                deps[structure.name]?.insert(fk.refTable)
            }
        }

        // Topological sort (Kahn) to assign depth levels
        var inDegree: [String: Int] = [:]
        for name in tables { inDegree[name] = 0 }
        for (from, targets) in deps {
            for _ in targets { inDegree[from, default: 0] += 0 } // init
        }
        // Count how many tables point TO each table (in-degree in dependency direction)
        var referencedBy: [String: Int] = [:]
        for name in tables { referencedBy[name] = 0 }
        for (_, targets) in deps {
            for t in targets { referencedBy[t, default: 0] += 1 }
        }

        // Assign levels: roots (most referenced / no FKs) go first
        var levels: [String: Int] = [:]
        var queue = tables.filter { deps[$0]?.isEmpty == true }.sorted()
        var currentLevel = 0
        var visited = Set<String>()

        if queue.isEmpty { queue = tables.sorted() } // fallback: no roots found

        while !queue.isEmpty {
            let nextQueue = queue
            for name in nextQueue {
                levels[name] = currentLevel
                visited.insert(name)
            }
            // Next level: tables that reference any table in current level
            var next: [String] = []
            for name in tables where !visited.contains(name) {
                let refersToVisited = deps[name]?.contains(where: { visited.contains($0) }) ?? false
                if refersToVisited { next.append(name) }
            }
            queue = next.sorted()
            currentLevel += 1
            // Safety: assign remaining tables
            if queue.isEmpty {
                let remaining = tables.filter { !visited.contains($0) }.sorted()
                for name in remaining { levels[name] = currentLevel }
            }
        }

        // Group by level
        var byLevel: [Int: [String]] = [:]
        for (name, level) in levels {
            byLevel[level, default: []].append(name)
        }

        // Position nodes in a grid by level
        let nodeWidth: CGFloat  = 220
        let nodeHeight: CGFloat = 200  // approx
        let hSpacing: CGFloat   = 80
        let vSpacing: CGFloat   = 60
        let startX: CGFloat     = 60
        let startY: CGFloat     = 60

        for (level, names) in byLevel {
            let sorted = names.sorted()
            for (col, name) in sorted.enumerated() {
                nodePositions[name] = CGPoint(
                    x: startX + CGFloat(col) * (nodeWidth + hSpacing),
                    y: startY + CGFloat(level) * (nodeHeight + vSpacing)
                )
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performLoad() async {
        guard !Task.isCancelled else { return }
        
        let schema = "public" // Use the same schema for tables and structures
        
        isLoading = true
        errorMessage = nil
        tableStructures.removeAll()
        nodePositions.removeAll()
        selectedTable = nil
        
        do {
            let tables = try await databaseService.fetchTables(schema: schema)
            
            if tables.isEmpty {
                errorMessage = "No hay tablas en esta base de datos"
                isLoading = false
                return
            }
            
            await withTaskGroup(of: (String, TableStructure?).self) { group in
                for table in tables {
                    group.addTask {
                        do {
                            let structure = try await self.databaseService.fetchTableStructure(table: table.name, schema: schema)
                            return (table.name, structure)
                        } catch {
                            print("Error loading structure for \(table.name): \(error)")
                            return (table.name, nil)
                        }
                    }
                }
                
                for await (tableName, structure) in group {
                    guard !Task.isCancelled else { return }
                    if let structure = structure {
                        self.tableStructures[tableName] = structure
                    }
                }
            }
            
            autoLayout()
            
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            errorMessage = error.errorDescription
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    // MARK: - Computed
    
    var tableNames: [String] {
        tableStructures.keys.sorted()
    }

    /// Posición lógica de un nodo incluyendo drag en curso
    func livePosition(for tableName: String) -> CGPoint {
        guard let pos = nodePositions[tableName] else { return .zero }
        let delta = nodeDragDeltas[tableName] ?? .zero
        return CGPoint(x: pos.x + delta.width / zoom, y: pos.y + delta.height / zoom)
    }

    /// Punto de anclaje en pantalla para una fila de columna dada
    /// side: .left = entrada (PK destino), .right = salida (FK origen)
    func anchorPoint(table: String, columnIndex: Int, side: AnchorSide, pan: CGSize) -> CGPoint {
        let nodeWidth: CGFloat = 220
        let headerHeight: CGFloat = 36
        let rowHeight: CGFloat = 28
        let pos = livePosition(for: table)
        let screenX = pos.x * zoom + pan.width
        let screenY = pos.y * zoom + pan.height
        let rowMidY = screenY + (headerHeight + rowHeight * CGFloat(columnIndex) + rowHeight / 2) * zoom
        switch side {
        case .left:  return CGPoint(x: screenX, y: rowMidY)
        case .right: return CGPoint(x: screenX + nodeWidth * zoom, y: rowMidY)
        }
    }

    enum AnchorSide { case left, right }
    
    var connections: [FKConnection] {
        var result: [FKConnection] = []
        
        for (_, structure) in tableStructures {
            for fk in structure.foreignKeys {
                if tableStructures[fk.refTable] != nil {
                    result.append(FKConnection(
                        fromTable: structure.name,
                        fromColumn: fk.column,
                        toTable: fk.refTable,
                        toColumn: fk.refColumn
                    ))
                }
            }
        }
        
        return result
    }
    
    var canvasSize: CGSize {
        CGSize(width: 2400, height: 1600)
    }
}

struct FKConnection: Identifiable, Hashable {
    let id = UUID()
    let fromTable: String
    let fromColumn: String
    let toTable: String
    let toColumn: String
}
