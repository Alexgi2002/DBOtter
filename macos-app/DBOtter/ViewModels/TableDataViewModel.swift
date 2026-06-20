//
//  TableDataViewModel.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

// MARK: - Pending Edit

struct CellEdit: Equatable {
    let rowIndex: Int
    let colIndex: Int
    let newValue: String
}

@MainActor
@Observable
final class TableDataViewModel {
    var queryResult: QueryResult?
    var isLoading = false
    var errorMessage: String?
    var isDisconnected = false
    var currentPage = 0
    var pageSize = 100
    var sortColumn: String? = nil
    var sortAscending = true
    var timeToRefresh: Int = 0
    var searchText: String = ""

    // Editing
    var pendingEdits: [CellEdit] = []
    var isSaving = false
    var saveError: String? = nil
    var primaryKeyColumn: String? = nil

    var hasPendingEdits: Bool { !pendingEdits.isEmpty }
    
    private let tableName: String
    private let databaseService = DatabaseService.shared
    private let taskHolder = TaskHolder()
    private var refreshTask: Task<Void, Never>?
    
    // MARK: - Computed
    
    init(tableName: String) {
        self.tableName = tableName
    }
    
    var hasNextPage: Bool {
        guard let result = queryResult else { return false }
        return result.rows.count >= pageSize
    }
    
    var totalRows: Int {
        queryResult?.rows.count ?? 0
    }
    
    /// Rows filtered by search text (local filtering on loaded page)
    var filteredRows: [[JSONValue]] {
        guard let result = queryResult, !searchText.isEmpty else {
            return queryResult?.rows ?? []
        }
        let lowerSearch = searchText.lowercased()
        return result.rows.filter { row in
            row.contains { value in
                value.displayString.lowercased().contains(lowerSearch)
            }
        }
    }
    
    /// Returns either original columns or filtered columns — always the same columns
    var displayColumns: [String] {
        queryResult?.columns ?? []
    }
    
    var isSearchActive: Bool {
        !searchText.isEmpty
    }
    
    var displayInfo: String {
        guard let result = queryResult else { return "Sin datos" }
        let start = currentPage * pageSize + 1
        let end = start + result.rows.count - 1
        var info = "Filas \(start)-\(end) • \(result.columns.count) columnas"
        if isSearchActive {
            info += " • \(filteredRows.count) coincidencias"
        }
        return info
    }
    
    // MARK: - Data Loading
    
    func loadData() async {
        refreshTask?.cancel()
        taskHolder.task?.cancel()
        
        taskHolder.task = Task {
            await performLoad()
        }
        
        await taskHolder.task?.value
    }
    
    func goToPage(_ page: Int) {
        guard page >= 0 else { return }
        currentPage = page
        Task { await loadData() }
    }
    
    func nextPage() {
        guard hasNextPage, !isLoading else { return }
        goToPage(currentPage + 1)
    }
    
    func previousPage() {
        guard currentPage > 0, !isLoading else { return }
        goToPage(currentPage - 1)
    }
    
    func refresh() {
        Task { await loadData() }
    }
    
    func setPageSize(_ size: Int) {
        pageSize = size
        currentPage = 0
        Task { await loadData() }
    }
    
    func sort(by column: String) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = true
        }
        applyLocalSort()
    }
    
    // MARK: - Auto Refresh
    
    func updateRefreshInterval(_ interval: Int) {
        timeToRefresh = interval
        restartAutoRefresh()
    }
    
    func restartAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        
        guard timeToRefresh > 0 else { return }
        
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(timeToRefresh) * 1_000_000_000)
                guard !Task.isCancelled, let self else { break }
                await self.loadData()
            }
        }
    }
    
    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Editing

    func loadPrimaryKey() async {
        guard primaryKeyColumn == nil else { return }
        do {
            let structure = try await databaseService.fetchTableStructure(table: tableName, schema: "public")
            primaryKeyColumn = structure.columns.first(where: { $0.isPrimaryKey })?.name
        } catch {
            // No PK found — editing will be disabled
        }
    }

    func stageEdit(rowIndex: Int, colIndex: Int, newValue: String) {
        // Replace existing edit for same cell or append
        if let existing = pendingEdits.firstIndex(where: { $0.rowIndex == rowIndex && $0.colIndex == colIndex }) {
            let current = displayValue(rowIndex: rowIndex, colIndex: colIndex)
            if newValue == current {
                pendingEdits.remove(at: existing)
            } else {
                pendingEdits[existing] = CellEdit(rowIndex: rowIndex, colIndex: colIndex, newValue: newValue)
            }
        } else {
            let current = displayValue(rowIndex: rowIndex, colIndex: colIndex)
            if newValue != current {
                pendingEdits.append(CellEdit(rowIndex: rowIndex, colIndex: colIndex, newValue: newValue))
            }
        }
    }

    func discardEdits() {
        pendingEdits = []
        saveError = nil
    }

    func saveEdits() async {
        guard !pendingEdits.isEmpty,
              let result = queryResult,
              let pkCol = primaryKeyColumn,
              let pkColIndex = result.columns.firstIndex(of: pkCol)
        else {
            saveError = "No se puede editar: la tabla no tiene clave primaria detectable."
            return
        }

        isSaving = true
        saveError = nil

        // Group edits by row to batch per-row UPDATEs
        let editsByRow = Dictionary(grouping: pendingEdits, by: { $0.rowIndex })
        let rows = isSearchActive ? filteredRows : result.rows

        var failed: [String] = []
        for (rowIndex, edits) in editsByRow.sorted(by: { $0.key < $1.key }) {
            guard let row = rows[safe: rowIndex] else { continue }
            let pkValue = row[safe: pkColIndex] ?? .null

            let setClauses = edits.map { edit -> String in
                let colName = result.columns[edit.colIndex]
                let escaped = edit.newValue.replacingOccurrences(of: "'", with: "''")
                return "\"\(colName)\" = '\(escaped)'"
            }.joined(separator: ", ")

            let pkLiteral: String
            switch pkValue {
            case .int(let v):    pkLiteral = String(v)
            case .double(let v): pkLiteral = String(v)
            case .string(let v): pkLiteral = "'\(v.replacingOccurrences(of: "'", with: "''"))'"
            default:             pkLiteral = "NULL"
            }

            let query = "UPDATE \"\(tableName)\" SET \(setClauses) WHERE \"\(pkCol)\" = \(pkLiteral);"
            do {
                _ = try await databaseService.executeQuery(query)
            } catch let error as APIError {
                failed.append(error.errorDescription ?? query)
            } catch {
                failed.append(error.localizedDescription)
            }
        }

        isSaving = false

        if failed.isEmpty {
            pendingEdits = []
            await loadData()
        } else {
            saveError = failed.joined(separator: "\n")
        }
    }

    func displayValue(rowIndex: Int, colIndex: Int) -> String {
        let rows = isSearchActive ? filteredRows : (queryResult?.rows ?? [])
        return rows[safe: rowIndex]?[safe: colIndex]?.displayString ?? ""
    }

    func pendingValue(rowIndex: Int, colIndex: Int) -> String? {
        pendingEdits.first(where: { $0.rowIndex == rowIndex && $0.colIndex == colIndex })?.newValue
    }
    
    // MARK: - Private Methods
    
    private func performLoad() async {
        guard !Task.isCancelled else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await databaseService.fetchTableData(
                table: tableName,
                limit: pageSize,
                offset: currentPage * pageSize
            )
            
            guard !Task.isCancelled else { return }
            
            queryResult = result
            isDisconnected = false
            applyLocalSort()
            
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            isDisconnected = error.isConnectionError
            errorMessage = error.errorDescription
        } catch {
            guard !Task.isCancelled else { return }
            isDisconnected = false
            errorMessage = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    private func applyLocalSort() {
        guard let result = queryResult,
              let sortColumn = sortColumn,
              let colIndex = result.columns.firstIndex(of: sortColumn) else { return }
        
        var sortedRows = result.rows
        sortedRows.sort { row1, row2 in
            let val1 = row1[safe: colIndex]
            let val2 = row2[safe: colIndex]
            return compareValues(val1, val2, ascending: sortAscending)
        }
        queryResult = QueryResult(columns: result.columns, rows: sortedRows)
    }
    
    private func compareValues(_ v1: JSONValue?, _ v2: JSONValue?, ascending: Bool) -> Bool {
        let result: Bool
        
        switch (v1, v2) {
        case (nil, nil):
            result = false
        case (nil, _):
            result = ascending
        case (_, nil):
            result = !ascending
        case (.string(let a), .string(let b)):
            result = a.localizedCompare(b) == .orderedAscending
        case (.int(let a), .int(let b)):
            result = a < b
        case (.double(let a), .double(let b)):
            result = a < b
        case (.bool(let a), .bool(let b)):
            result = !a && b
        default:
            let a = v1?.displayString ?? ""
            let b = v2?.displayString ?? ""
            result = a.localizedCompare(b) == .orderedAscending
        }
        
        return ascending ? result : !result
    }
}

// Safe array access
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
