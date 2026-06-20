//
//  SidebarView.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import SwiftUI
import SwiftData

struct SidebarView: View {
    @State private var viewModel = SidebarViewModel()
    let onOpenTable: (String, UUID, String, String) -> Void
    let onOpenDiagram: (UUID, String) -> Void
    let onReconnected: (UUID) -> Void
    @State private var showingNewConnection = false
    @State private var showingEditConnection = false
    @State private var connectionToEdit: SavedConnection?
    @State private var selectedTable: String? = nil

    @Environment(ToastManager.self) private var toastManager

    var body: some View {
        List(selection: $selectedTable) {
            if viewModel.savedConnections.isEmpty {
                emptyStateSection
            } else {
                connectionsSection
            }
        }
        .onAppear { viewModel.onReconnected = onReconnected }
        .searchable(text: $viewModel.searchText, placement: .sidebar, prompt: "Buscar por tablas")
        .searchToolbarBehavior(.automatic)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .toolbar {
            Button(action: { showingNewConnection = true }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.glass)
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        .listStyle(.sidebar)
        .sheet(isPresented: $showingNewConnection) {
            ConnectionFormView(
                mode: .create,
                onConnect: { _, _, _, _, _, _, _, _ in },
                onSave: { name, engine, host, port, username, password, sslMode, ssh in
                    let connection = SavedConnection(
                        name: name, engine: engine,
                        host: host, port: port,
                        username: username, password: password,
                        sslMode: sslMode,
                        sshEnabled: ssh.enabled, sshHost: ssh.host,
                        sshPort: ssh.port, sshUsername: ssh.username,
                        sshPassword: ssh.resolvedPassword,
                        sshPrivateKey: ssh.resolvedPrivateKey,
                        sshKeyPath: ssh.resolvedKeyPath
                    )
                    viewModel.addConnection(connection)
                },
                onEdit: { _, _, _, _, _, _, _, _, _ in }
            )
        }
        .sheet(isPresented: $showingEditConnection) {
            ConnectionFormView(
                mode: .edit,
                onConnect: { _, _, _, _, _, _, _, _ in },
                onSave: { _, _, _, _, _, _, _, _ in },
                onEdit: { name, engine, host, port, username, password, sslMode, ssh, connectionId in
                    if let connection = connectionToEdit {
                        // Update the existing connection
                        connection.name = name
                        connection.host = host
                        connection.port = port
                        connection.username = username
                        connection.password = password
                        connection.sslMode = sslMode
                        connection.sshEnabled = ssh.enabled
                        connection.sshHost = ssh.host
                        connection.sshPort = ssh.port
                        connection.sshUsername = ssh.username
                        connection.sshPassword = ssh.resolvedPassword
                        connection.sshPrivateKey = ssh.resolvedPrivateKey
                        connection.sshKeyPath = ssh.resolvedKeyPath
                        viewModel.editConnection(connection)
                    }
                }
            )
        }
        .alert("Error", isPresented: .constant(viewModel.connectionErrors.values.contains(where: { !$0.isEmpty }))) {
            Button("OK") { }
        } message: {
            if let error = viewModel.connectionErrors.values.first(where: { !$0.isEmpty }) {
                Text(error)
            }
        }
    }

    // MARK: - Sections

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 40))
                    .foregroundColor(.secondary)

                Text("Sin conexiones guardadas")
                    .font(.headline)
                    .foregroundColor(.secondary)

                Text("Crea tu primera conexión para empezar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: { showingNewConnection = true }) {
                    Label("Crear conexión", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

private var connectionsSection: some View {
        //        let list: [SavedConnection] = viewModel.savedConnections

    return ForEach(viewModel.savedConnections) { connection in
        ConnectionFolderView(
            connection: connection,
            isExpanded: viewModel.isConnectionExpanded(connection),
            isLoading: viewModel.isConnectionLoading(connection),
            error: viewModel.connectionError(connection),
            databases: viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? viewModel.databases(for: connection) : viewModel.databases(for: connection).filter {
                return $0.name.lowercased().contains(viewModel.searchText.lowercased())
            },
            onToggle: { viewModel.toggleConnectionExpansion(connection) },
            onRefresh: { Task { await viewModel.refreshConnection(connection) } },
            onDelete: { viewModel.deleteConnection(connection) },
            databaseContent: { db in
                DatabaseFolderView(
                    dbID: db.id,
                    dbName: db.name,
                    isExpanded: viewModel.isDatabaseExpanded(db.name, for: connection),
                    isLoading: viewModel.isDatabaseLoading(db.name, for: connection),
                    error: viewModel.databaseError(db.name, for: connection),
                    tables: viewModel.tables(for: db.name, in: connection),
                    onToggle: { viewModel.toggleDatabaseExpansion(db.name, for: connection) },
                    onSelectTable: { tableName, dbName in
                        viewModel.selectTable(tableName, from: connection)
                        onOpenTable(tableName, connection.id, dbName, connection.name)
                    },
                    onRefresh: { Task { await viewModel.loadTables(for: db.name, in: connection) } },
                    onOpenDiagram: { _, dbName in
                        onOpenDiagram(connection.id, dbName)
                    }
                )
            },
            onEditConnection: { editedConnection in
                connectionToEdit = editedConnection
                showingEditConnection = true
            },
            setShowingEditConnection: { showing in
                showingEditConnection = showing
            },
            onOpenDiagram: {d,s in
                onOpenDiagram(d,s)
            }
                    
            )
        }
    }
}

// MARK: - Database Folder View

struct DatabaseFolderView: View {
    let dbID: String
    let dbName: String
    let isExpanded: Bool
    let isLoading: Bool
    let error: String?
    let tables: [TableEntity]
    let onToggle: () -> Void
    let onSelectTable: (String, String) -> Void
    let onRefresh: () async -> Void
    let onOpenDiagram: (String, String) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { _ in onToggle() }
        )) {
            if isLoading {
                loadingView("Cargando tablas...")
            } else if let error = error {
                errorView(error, retry: onRefresh)
            } else if tables.isEmpty {
                emptyView("Sin tablas")
            } else {
                ForEach(tables) { table in
                    TableRowView(table: table, isSelected: false) {
                        onSelectTable(table.name, dbName)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cylinder.split.1x2")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                Text(dbName)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if isLoading {
                    ProgressView().controlSize(.mini)
                }
                if isExpanded {
                    Spacer()
                    Button("Ver diagrama", action: {
                        onOpenDiagram(dbID, dbName)
                    })
                        .buttonStyle(.glass)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .onTapGesture {
            withAnimation(){
                onToggle()
            }
        }
    }
}

// MARK: - Connection Folder View

struct ConnectionFolderView: View {
    let connection: SavedConnection
    let isExpanded: Bool
    let isLoading: Bool
    let error: String?
    let databases: [DatabaseInfo]
    let onToggle: () -> Void
    let onRefresh: () async -> Void
    let onDelete: () -> Void
    let databaseContent: (DatabaseInfo) -> DatabaseFolderView
    let onEditConnection: (SavedConnection) -> Void
    let setShowingEditConnection: (Bool) -> Void
    let onOpenDiagram: (UUID, String) -> Void

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { _ in onToggle() }
        )) {
            if isLoading {
                loadingView("Cargando bases de datos...")
            } else if let error = error {
                errorView(error, retry: onRefresh)
            } else {
                ForEach(databases) { db in
                    databaseContent(db)
                        .padding(.leading, 4)
                }
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(connection.engineType.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(connection.engineType.iconName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 26, height: 26)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(connection.displayName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.mini)
                } else if error != nil {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                } else if !databases.isEmpty {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeIn(duration: 200)){
                    onToggle()
                }
            }
        }
        .contextMenu {
            Button("Actualizar", action: { Task { await onRefresh() } })
            Divider()
            Button("Editar", action: {
                onEditConnection(connection)
                setShowingEditConnection(true)
            })
            Divider()
            Button("Eliminar", role: .destructive, action: onDelete)
        }
    }
}

struct TableRowView: View {
    let table: TableEntity
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "tablecells")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))

                Text(table.name)
//                    .font(.system(., design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared View Builders

private func loadingView(_ text: String) -> some View {
    HStack {
        Spacer()
        ProgressView(text).controlSize(.small)
        Spacer()
    }
    .padding(.vertical, 8)
}

private func errorView(_ error: String, retry: @escaping () async -> Void) -> some View {
    VStack(spacing: 8) {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 8)

        Button("Reintentar") { Task { await retry() } }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }
    .padding(.vertical, 8)
}

private func emptyView(_ text: String) -> some View {
    HStack {
        Spacer()
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
        Spacer()
    }
    .padding(.vertical, 8)
}

#Preview {
    SidebarView(onOpenTable: { _, _, _, _ in }, onOpenDiagram: { _, _ in }, onReconnected: { _ in })
        .frame(width: 320, height: 700)
}
