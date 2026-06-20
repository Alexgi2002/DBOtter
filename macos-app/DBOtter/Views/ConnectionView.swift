//
//  ConnectionView.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import SwiftUI
import SwiftData

struct ConnectionView: View {
    @State private var viewModel = ConnectionViewModel()
    @Environment(\.modelContext) private var modelContext
    @Binding var isConnected: Bool
    @State private var showingNewConnection = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            
            if !viewModel.savedConnections.isEmpty {
                savedConnectionsSection
            }
            
            newConnectionButton
            
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingNewConnection) {
            ConnectionFormView(
                mode: .connect,
                onConnect: { engine, host, port, username, password, sslMode, filePath, ssh in
                    print("🔧 ConnectionView.onConnect received SSH: enabled=\(ssh.enabled) host=\(ssh.host) port=\(ssh.port) user=\(ssh.username) passLen=\(ssh.resolvedPassword.count) keyPath=\(ssh.resolvedKeyPath) keyLen=\(ssh.resolvedPrivateKey.count)")
                    await viewModel.connect(
                        engine: engine, host: host, port: port,
                        username: username, password: password,
                        sslMode: sslMode, filePath: filePath,
                        sshEnabled: ssh.enabled, sshHost: ssh.host,
                        sshPort: ssh.port, sshUsername: ssh.username,
                        sshPassword: ssh.resolvedPassword,
                        sshPrivateKey: ssh.resolvedPrivateKey,
                        sshKeyPath: ssh.resolvedKeyPath
                    )
                },
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
                    viewModel.saveConnection(connection)
                },
                onEdit: { _, _, _, _, _, _, _, _, _ in }
            )
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Conexión a Base de Datos", systemImage: "cylinder")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Selecciona una conexión guardada o crea una nueva")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var savedConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Conexiones guardadas")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(viewModel.savedConnections) { connection in
                        SavedConnectionCard(connection: connection) {
                            Task { await viewModel.connect(using: connection) }
                        } onDelete: {
                            viewModel.deleteConnection(connection)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private var newConnectionButton: some View {
        VStack(spacing: 16) {
            Divider()
            
            Button(action: { showingNewConnection = true }) {
                Label("Nueva Conexión", systemImage: "plus.circle.fill")
                    .font(.body)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            Text("Configura motor, credenciales y conectate al servidor")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Saved Connection Card

struct SavedConnectionCard: View {
    let connection: SavedConnection
    let onConnect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(connection.engineType.iconName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 10, height: 10)
                Text(connection.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                if let lastUsed = connection.lastUsedAt {
                    Text(lastUsed, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Text(connection.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            HStack(spacing: 8) {
                Button(action: onConnect) {
                    Label("Conectar", systemImage: "bolt")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Spacer()
                
                Menu {
                    Button("Eliminar", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
    }
    
}

#Preview {
    ConnectionView(isConnected: .constant(false))
        .frame(width: 500, height: 700)
}
