//
//  TableDataView.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import SwiftUI

enum TableViewMode: String, CaseIterable {
    case structure = "Estructura"
    case data      = "Datos"
}

struct TableDataView: View {
    @State private var viewModel: TableDataViewModel
    @State private var selectedView: TableViewMode = .data
    @State private var showingSQLSheet = false
    @State private var showingExportSheet = false
    @State private var editingCell: (row: Int, col: Int)? = nil

    @State private var selectedTab = false

    let tableName: String
    let connectionId: UUID
    let dbName: String

    init(tableName: String, connectionId: UUID, dbName: String) {
        self.tableName = tableName
        self.connectionId = connectionId
        self.dbName = dbName
        self.viewModel = TableDataViewModel(tableName: tableName)
    }

    var body: some View {
        VStack(spacing: 0) {
            tableHeader
            menuToolbar
            contentView
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await viewModel.loadData()
            await viewModel.loadPrimaryKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: .connectionReconnected)) { note in
            guard let id = note.userInfo?["connectionId"] as? UUID, id == connectionId else { return }
            Task { await viewModel.loadData() }
        }
        .onChange(of: viewModel.timeToRefresh) { _, newValue in
            if newValue > 0 { viewModel.restartAutoRefresh() } else { viewModel.stopAutoRefresh() }
        }
        .sheet(isPresented: $showingSQLSheet) { SQLQueryView(tableName: tableName) }
        .sheet(isPresented: $showingExportSheet) { ExportView(tableName: tableName) }
    }

    // MARK: - Header

    private var tableHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(tableName).font(.title2).fontWeight(.semibold)
                Text(viewModel.displayInfo).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { showingExportSheet = true }) { Label("Exportar", systemImage: "square.and.arrow.up") }
                .help("Exportar tabla")
            Button(action: { showingSQLSheet = true }) { Label("SQL", systemImage: "pencil.and.scribble") }
                .help("Editor SQL")
            Button(action: { Task { await viewModel.loadData() } }) { Image(systemName: "arrow.clockwise") }
                .disabled(viewModel.isLoading)
                .help("Recargar datos")
            Picker("Auto Refrescar", selection: $viewModel.timeToRefresh) {
                Text("Off").tag(0)
                Text("5 sec").tag(5)
                Text("10 sec").tag(10)
                Text("30 sec").tag(30)
                Text("1 min").tag(60)
                Text("5 min").tag(300)
            }
            .frame(width: 140)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Toolbar

    private var menuToolbar: some View {
        HStack {
            Picker("", selection: $selectedView) {
                Text("Estructura").tag(TableViewMode.structure)
                Text("Datos").tag(TableViewMode.data)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer(minLength: 150)

            if viewModel.isSearchActive {
                HStack(spacing: 2) {
                    Text("\(viewModel.filteredRows.count)").font(.caption).foregroundColor(.accentColor).fontWeight(.semibold)
                    Text("coincidencias").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.08))
                .cornerRadius(4)
            }

            Divider().frame(height: 16)

            TextField("Buscar en página actual...", text: $viewModel.searchText)
                .textFieldStyle(.plain).frame(width: 200)

            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let sortColumn = viewModel.sortColumn {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down").font(.caption)
                    Text(sortColumn).font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(4)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        switch selectedView {
        case .structure: TableStructureView(tableName: tableName)
        case .data:      dataContentView
        }
    }

    @ViewBuilder
    private var dataContentView: some View {
        if viewModel.isLoading {
            ProgressView("Cargando datos...").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isDisconnected {
            DisconnectedView(viewModel: $viewModel)
        } else if let result = viewModel.queryResult {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.hasPendingEdits || viewModel.saveError != nil {
                    pendingEditsBar
                }
                
                DynamicTableView(
                    data: convertQueryResultToDisplayRows(result),
                    columns: result.columns
                )
            }
        } else if let error = viewModel.errorMessage {
            ErrorView(message: error) { Task { await viewModel.loadData() } }
        } else {
            ContentUnavailableView("Sin datos", systemImage: "tablecells", description: Text("No hay datos para mostrar"))
        }
    }

    // MARK: - Pending Edits Bar

    private var pendingEditsBar: some View {
        HStack(spacing: 10) {
            if let error = viewModel.saveError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                Spacer()
                Button("Descartar") { viewModel.discardEdits() }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Image(systemName: "pencil.circle.fill").foregroundStyle(.blue)
                Text("\(viewModel.pendingEdits.count) cambio\(viewModel.pendingEdits.count == 1 ? "" : "s") sin guardar")
                    .font(.caption).fontWeight(.medium)
                Spacer()
                Button("Descartar") { viewModel.discardEdits(); editingCell = nil }
                    .buttonStyle(.bordered).controlSize(.small)
                Button(action: { Task { await viewModel.saveEdits() } }) {
                    if viewModel.isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Guardar", systemImage: "checkmark")
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(viewModel.isSaving)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(viewModel.saveError != nil ? Color.red.opacity(0.08) : Color.accentColor.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Disconnected Panel

    

    // MARK: - Data Table

    // MARK: - Data Table

    // MARK: - Convert QueryResult to displayable rows

    private func convertQueryResultToDisplayRows(_ result: QueryResult) -> [[String]] {
        return result.rows.map { row in
            row.map { value in
                value.displayString
            }
        }
    }
}

// MARK: - Cell View (read-only, used in SQL query results)

struct CellView: View {
    let value: JSONValue

    var body: some View {
        Text(value.displayString)
            .font(.system(.caption, design: .monospaced))
            .foregroundColor(value == .null ? .secondary : .primary)
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(value == .null ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
    }
}

// MARK: - Editable Cell View

struct EditableCellView: View {
    let value: JSONValue
    let pendingValue: String?
    let isEditing: Bool
    let isModified: Bool
    let canEdit: Bool
    let onDoubleClick: () -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var editText: String = ""
    @FocusState private var focused: Bool

    private var displayText: String { pendingValue ?? value.displayString }
    private var isNull: Bool { value == .null && pendingValue == nil }

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .font(.system(.caption, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1.5))
                    .focused($focused)
                    .onAppear {
                        editText = pendingValue ?? (value == .null ? "" : value.displayString)
                        focused = true
                    }
                    .onSubmit { onCommit(editText) }
                    .onKeyPress(.escape) { onCancel(); return .handled }
            } else {
                Text(isNull ? "NULL" : displayText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isNull ? Color.secondary : (isModified ? Color.accentColor : Color.primary))
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isModified ? Color.accentColor.opacity(0.08) :
                        isNull ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear
                    )
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if canEdit { onDoubleClick() }
                    })
                    .help(canEdit ? "Doble clic para editar" : "Sin clave primaria: edición deshabilitada")
            }
        }
    }
}

// MARK: - SQL Query Sheet

struct SQLQueryView: View {
    @State private var queryText: String = ""
    @State private var queryResult: QueryResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    let tableName: String
    @State private var codeEditorViewModel = CodeEditorViewModel()
    private let databaseService = DatabaseService.shared
    private let schemaCache = SchemaCache.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Editor SQL", systemImage: "pencil.and.scribble").font(.headline)
                Spacer()
                Button("Cerrar") { dismiss() }
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Query:").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    ZStack(alignment: .topLeading) {
                        CodeEditorView(viewModel: codeEditorViewModel)
                            .frame(minHeight: 80, maxHeight: 150)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                            .onChange(of: codeEditorViewModel.text) { _, newValue in queryText = newValue }
                        SQLAutocompletePopover(viewModel: codeEditorViewModel)
                    }
                    VStack(spacing: 8) {
                        Button(action: { executeQuery() }) {
                            if isLoading { ProgressView().controlSize(.small) }
                            else { Image(systemName: "play.fill") }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isLoading || queryText.isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                        Button(action: { queryText = defaultQuery; codeEditorViewModel.text = defaultQuery }) {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding()

            Divider()

            if isLoading {
                ProgressView("Ejecutando query...").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ErrorView(message: error) { executeQuery() }
            } else if let result = queryResult {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(result.rows.count) filas • \(result.columns.count) columnas")
                        .font(.caption).foregroundColor(.secondary).padding(.horizontal)
                    ScrollView([.horizontal, .vertical]) {
                        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                            GridRow {
                                ForEach(Array(result.columns.enumerated()), id: \.offset) { _, col in
                                    Text(col).font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color(NSColor.controlBackgroundColor))
                                }
                            }
                            .overlay(alignment: .bottom) { Divider() }
                            ForEach(Array(result.rows.enumerated()), id: \.offset) { rowIndex, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in CellView(value: cell) }
                                }
                                .background(rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
                                .overlay(alignment: .bottom) { Divider().opacity(0.2) }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Ejecuta una query", systemImage: "terminal",
                    description: Text("Escribe una consulta SQL y presiona Ejecutar"))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            queryText = defaultQuery
            codeEditorViewModel.text = defaultQuery
            Task {
                try? await schemaCache.loadIfNeeded()
            }
        }
    }

    private var defaultQuery: String { "SELECT * FROM \"\(tableName)\" LIMIT 100;" }

    private func executeQuery() {
        guard !queryText.isEmpty else { return }
        isLoading = true; errorMessage = nil; queryResult = nil
        Task {
            do { queryResult = try await databaseService.executeQuery(queryText) }
            catch let error as APIError { errorMessage = error.errorDescription }
            catch { errorMessage = "Error: \(error.localizedDescription)" }
            isLoading = false
        }
    }
}

#Preview {
    TableDataView(tableName: "users", connectionId: UUID(), dbName: "mydb")
        .frame(width: 800, height: 600)
}
