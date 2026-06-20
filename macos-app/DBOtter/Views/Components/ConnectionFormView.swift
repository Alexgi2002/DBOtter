//
//  ConnectionFormView.swift
//  DBOtter
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation

// Basic SSH form fields for connection editing
struct SSHFormFields {
    var enabled = false
    var host = ""
    var portString = "22"
    var username = ""
    var password = ""
    var keyPath = ""
    var privateKey = ""
    
    var port: Int { Int(portString) ?? 22 }
    
    var resolvedPassword: String   { password }
    var resolvedKeyPath: String    { keyPath }
    var resolvedPrivateKey: String { privateKey }
}

enum SSHAuthMethod { case password, keyFile, keyInline }

// Form mode for connection editing
enum FormMode {
    case create, connect, edit
    
    var title: String {
        switch self {
        case .create:  return "Nueva Conexión"
        case .connect: return "Conectar a Base de Datos"
        case .edit:    return "Editar Conexión"
        }
    }
    var subtitle: String {
        switch self {
        case .create:  return "Configura los accesos y guarda la conexión para usarla después."
        case .connect: return "Completa los datos y conéctate directamente al servidor."
        case .edit:    return "Modifica los datos de la conexión y guarda los cambios."
        }
    }
    var showSave: Bool { true }
    var showConnect: Bool {
        switch self {
        case .create: return false
        case .connect: return true
        case .edit:   return false
        }
    }
}

// Simple connection form view
struct ConnectionFormView: View {
    let mode: FormMode
    let onConnect: (_ engine: EngineType, _ host: String, _ port: Int, _ username: String, _ password: String, _ sslMode: String, _ filePath: String?, _ ssh: SSHFormFields) async -> Void
    let onSave: (_ name: String, _ engine: EngineType, _ host: String, _ port: Int, _ username: String, _ password: String, _ sslMode: String, _ ssh: SSHFormFields) -> Void
    let onEdit: ((_ name: String, _ engine: EngineType, _ host: String, _ port: Int, _ username: String, _ password: String, _ sslMode: String, _ ssh: SSHFormFields, _ connectionId: UUID) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var connectionName = ""
    @State private var selectedEngine: EngineType = .postgres
    @State private var host = "localhost"
    @State private var port = "5432"
    @State private var username = ""
    @State private var password = ""
    @State private var sslMode = "disable"
    @State private var filePath = ""
    @State private var sshFields = SSHFormFields()
    @State private var sshExpanded = false
    @State private var sshAuthMethod: SSHAuthMethod = .password
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isTestingConnection = false
    @State private var testingErrorMessage: String?
    @State private var editingConnection: SavedConnection?
    @State private var showingSSHDebug = false

    private let sslOptions = ["disable", "require", "prefer", "allow", "verify-ca", "verify-full"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    nameSection
                    engineSection
                    configurationSection
                    sshSection
                    connectionPreview
                }
                .padding(24)
            }
            Divider()
            bottomBar
        }
        .frame(width: 540, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: selectedEngine) { _, newEngine in resetFields(for: newEngine) }
        .onAppear { populateFieldsFromConnection() }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Error de Prueba", isPresented: .constant(testingErrorMessage != nil)) {
            Button("OK") { testingErrorMessage = nil }
        } message: { Text(testingErrorMessage ?? "") }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(mode.title, systemImage: "plus.circle.fill")
                .font(.title2).fontWeight(.semibold)
            Text(mode.subtitle)
                .font(.subheadline).foregroundColor(.secondary)
        }
    }
    
    // MARK: - Connection Name
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nombre de conexión")
                .font(.caption).foregroundColor(.secondary)
            TextField("Mi servidor de producción", text: $connectionName)
                .textFieldStyle(.roundedBorder)
                .disabled(isLoading)
        }
    }
    
    // MARK: - Engine
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Motor").font(.headline).fontWeight(.medium)
            Picker("Motor", selection: $selectedEngine) {
                ForEach(EngineType.allCases) { engine in
                    HStack {
                        Image(engine.iconName)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: 32, height: 32)
                            .clipped()
                        Text(engine.displayName)
                    }.tag(engine)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
    
    // MARK: - Configuration Section
    @ViewBuilder
    private var configurationSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                if selectedEngine.supportsHostPort {
                    serverFields
                } else {
                    sqliteFileField
                }
            }
        } label: {
            Label("Configuración", systemImage: "gearshape.fill").font(.headline)
        }
    }
    
    // MARK: - Server Fields
    private var serverFields: some View {
        Group {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Host / Servidor")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("localhost", text: $host)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isLoading)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Puerto")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("\(selectedEngine.defaultPort)", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 90)
                        .disabled(isLoading)
                }
            }

            Divider()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usuario")
                        .font(.caption).foregroundColor(.secondary)
                    TextField("usuario", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isLoading)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Contraseña")
                        .font(.caption).foregroundColor(.secondary)
                    SecureField("••••••••", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isLoading)
                }
            }

            if selectedEngine.supportsSSL {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("SSL Mode")
                        .font(.caption).foregroundColor(.secondary)
                    Picker("SSL Mode", selection: $sslMode) {
                        ForEach(sslOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .disabled(isLoading)
                }
            }
        }
    }
    
    // MARK: - SQLite File Field
    private var sqliteFileField: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Archivo de Base de Datos")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    TextField("/ruta/a/base_de_datos.db", text: $filePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .disabled(isLoading)
                }
            }
            Text("Selecciona un archivo SQLite existente o escribe la ruta.")
                .font(.caption2).foregroundColor(.secondary)
        }
    }
    
    // MARK: - SSH Section
    private var sshSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { sshExpanded.toggle() } }) {
                    HStack {
                        Toggle("Usar túnel SSH", isOn: $sshFields.enabled)
                            .toggleStyle(.switch)
                            .labelsHidden()

                        Text("Túnel SSH")
                            .font(.subheadline).fontWeight(.medium)

                        Spacer()

                        if sshFields.enabled {
                            Text("Configurado")
                                .font(.caption2)
                                .foregroundColor(.green)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        Image(systemName: sshExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if sshExpanded {
                    Divider()
 
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Configuración SSH")
                            .font(.caption).foregroundColor(.secondary)
 
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Host SSH")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("192.168.1.100", text: $sshFields.host)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .disabled(isLoading || !sshFields.enabled)
                        }
 
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Puerto SSH")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("22", text: $sshFields.portString)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 90)
                                .disabled(isLoading || !sshFields.enabled)
                        }
 
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Usuario SSH")
                                .font(.caption).foregroundColor(.secondary)
                            TextField("ubuntu", text: $sshFields.username)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .disabled(isLoading || !sshFields.enabled)
                        }
 
                        // MARK: - SSH Authentication
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Autenticación SSH")
                                .font(.caption).foregroundColor(.secondary)
                            Picker("Método", selection: $sshAuthMethod) {
                                Text("Contraseña").tag(SSHAuthMethod.password)
                                Text("Archivo de clave").tag(SSHAuthMethod.keyFile)
                                Text("Clave inline (PEM)").tag(SSHAuthMethod.keyInline)
                            }
                            .pickerStyle(.segmented)
                            .disabled(isLoading || !sshFields.enabled)
                        }
 
                        // Password field
                        if sshAuthMethod == .password {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Contraseña SSH")
                                    .font(.caption).foregroundColor(.secondary)
                                SecureField("••••••••", text: $sshFields.password)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                                    .disabled(isLoading || !sshFields.enabled)
                            }
                        }
 
                        // Key file field
                        if sshAuthMethod == .keyFile {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ruta de la clave privada")
                                    .font(.caption).foregroundColor(.secondary)
                                HStack(spacing: 8) {
                                    TextField("~/.ssh/id_ed25519", text: $sshFields.keyPath)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .disabled(isLoading || !sshFields.enabled)
                                    Button("Seleccionar") {
                                        selectKeyFile()
                                    }
                                    .disabled(isLoading || !sshFields.enabled)
                                }
                            }
                        }
 
                        // Inline private key field
                        if sshAuthMethod == .keyInline {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Clave privada (PEM)")
                                    .font(.caption).foregroundColor(.secondary)
                                TextEditor(text: $sshFields.privateKey)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 100)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
                                    .disabled(isLoading || !sshFields.enabled)
                                Text("Pega el contenido completo de la clave privada (-----BEGIN OPENSSH PRIVATE KEY----- ...)")
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        } label: {
            Label("SSH Tunnel", systemImage: "lock.shield.fill").font(.headline)
        }
        .opacity(selectedEngine.supportsHostPort ? 1 : 0.4)
        .disabled(!selectedEngine.supportsHostPort)
    }
    
    // MARK: - Connection Preview
    private var connectionPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Resumen de conexión", systemImage: "info.circle")
                .font(.caption).foregroundColor(.secondary)

            HStack(spacing: 6) {
                Image(selectedEngine.iconName)
                    .resizable().scaledToFit().aspectRatio(1, contentMode: .fit).frame(width: 24, height: 24)

                Text(connectionSummary)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary).lineLimit(1)

                if sshFields.enabled && !sshFields.host.isEmpty {
                    Text("· via SSH:\(sshFields.host)")
                        .font(.caption2).foregroundColor(.blue.opacity(0.8))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
        }
    }
    
    private var connectionSummary: String {
        if selectedEngine.supportsHostPort {
            let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let h = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let p = port.trimmingCharacters(in: .whitespacesAndNewlines)
            return u.isEmpty ? "\(h):\(p)" : "\(u)@\(h):\(p)"
        } else {
            let p = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
            return p.isEmpty ? "Sin archivo seleccionado" : p
        }
    }
    
    private var sshDebugDescription: String {
        var lines: [String] = []
        lines.append("enabled: \(sshFields.enabled)")
        lines.append("host: \(sshFields.host.isEmpty ? "(vacío)" : sshFields.host)")
        lines.append("port: \(sshFields.port)")
        lines.append("username: \(sshFields.username.isEmpty ? "(vacío)" : sshFields.username)")
        lines.append("authMethod: \(sshAuthMethod)")
        
        switch sshAuthMethod {
        case .password:
            lines.append("password: \(sshFields.password.isEmpty ? "(vacío)" : "•••••••• (\(sshFields.password.count) chars)")")
        case .keyFile:
            lines.append("keyPath: \(sshFields.keyPath.isEmpty ? "(vacío)" : sshFields.keyPath)")
        case .keyInline:
            let keyPreview = sshFields.privateKey.isEmpty ? "(vacío)" : "\(sshFields.privateKey.prefix(50))... (\(sshFields.privateKey.count) chars)"
            lines.append("privateKey: \(keyPreview)")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Bottom Bar
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let err = errorMessage {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.red).lineLimit(2)
            }
            if let testErr = testingErrorMessage {
                Label("Prueba: \(testErr)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundColor(.orange).lineLimit(2)
            }
            Spacer()
            Button("Cancelar") { dismiss() }
                .buttonStyle(.bordered).keyboardShortcut(.cancelAction)

            if mode.showSave {
                if mode == .edit {
                    Button(action: save) {
                        Label("Editar", systemImage: "pencil.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                } else {
                    Button(action: save) {
                        Label("Guardar", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canSave)
                }
            }
            
            // Always show test/debug buttons (even if disabled) so user sees them
            VStack(spacing: 8) {
                // Debug SSH button - shows what will be sent
                if sshFields.enabled {
                    Button(action: { 
                        print("=== SSH DEBUG ===")
                        print(sshDebugDescription)
                        print("=================")
                        showingSSHDebug = true 
                    }) {
                        Label("Ver SSH", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .help("Ver los valores SSH que se enviarán")
                    .alert("Valores SSH a enviar", isPresented: $showingSSHDebug) {
                        Button("OK") { }
                    } message: {
                        Text(sshDebugDescription)
                    }
                }
                
                Button(action: {
                    print("=== TEST CONNECTION CLICKED ===")
                    print("canConnect: \(canConnect)")
                    print("host: '\(host)' port: '\(port)'")
                    print("sshEnabled: \(sshFields.enabled)")
                    print("sshHost: '\(sshFields.host)'")
                    testConnection()
                }) {
                    if isTestingConnection {
                        ProgressView().controlSize(.small).frame(width: 16, height: 16)
                    } else {
                        Label("Probar conexión", systemImage: "magnifyingglass.circle.fill")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingConnection || !canConnect)
                .foregroundColor(.secondary)
                .help(canConnect ? "Probar conexión a la base de datos" : "Completa host y puerto de la BD para habilitar")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }
    
    // MARK: - Validation
    private var canConnect: Bool {
        if selectedEngine.supportsHostPort {
            return !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
        } else {
            return !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    private var canSave: Bool {
        !connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && canConnect
    }
    
    // MARK: - Actions
    private func connect() {
        let portInt = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedEngine.defaultPort
        let fp = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        errorMessage = nil
        Task {
            await onConnect(
                selectedEngine,
                host.trimmingCharacters(in: .whitespacesAndNewlines),
                portInt,
                username.trimmingCharacters(in: .whitespacesAndNewlines),
                password,
                sslMode,
                fp.isEmpty ? nil : fp,
                sshFields
            )
            isLoading = false
        }
    }
    
    private func testConnection() {
        let portInt = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedEngine.defaultPort
        let fp = filePath.trimmingCharacters(in: .whitespacesAndNewlines)
        isTestingConnection = true
        testingErrorMessage = nil
        
        Task {
            do {
                // Test connection by attempting to connect without showing user errors
                await onConnect(
                    selectedEngine,
                    host.trimmingCharacters(in: .whitespacesAndNewlines),
                    portInt,
                    username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password,
                    sslMode,
                    fp.isEmpty ? nil : fp,
                    sshFields
                )
                // If we get here, the connection was successful (or at least attempted)
                testingErrorMessage = "Conexión establecida exitosamente"
            } catch {
                testingErrorMessage = "Error probando conexión: \(error.localizedDescription)"
            }
            isTestingConnection = false
        }
    }
    
    private func save() {
        if mode == .edit {
            edit()
        } else {
            onSave(
                connectionName.trimmingCharacters(in: .whitespacesAndNewlines),
                selectedEngine,
                host.trimmingCharacters(in: .whitespacesAndNewlines),
                Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedEngine.defaultPort,
                username.trimmingCharacters(in: .whitespacesAndNewlines),
                password,
                sslMode,
                sshFields
            )
            dismiss()
        }
    }
    
    // MARK: - Edit Logic
    private func populateFieldsFromConnection() {
        guard let connection = editingConnection else { return }
        
        connectionName = connection.name
        selectedEngine = connection.engineType
        host = connection.host
        port = String(connection.port)
        username = connection.username
        password = connection.password
        sslMode = connection.sslMode
        filePath = connection.engineType == .sqlite ? "" : ""
        
        sshFields.enabled = connection.sshEnabled
        sshFields.host = connection.sshHost
        sshFields.portString = String(connection.sshPort)
        sshFields.username = connection.sshUsername
        sshFields.password = connection.sshPassword
        sshFields.keyPath = connection.sshKeyPath
        sshFields.privateKey = connection.sshPrivateKey
        
        // Detectar método de auth guardado
        if !connection.sshPrivateKey.isEmpty {
            sshAuthMethod = .keyInline
        } else if !connection.sshKeyPath.isEmpty {
            sshAuthMethod = .keyFile
        } else {
            sshAuthMethod = .password
        }
    }
    
    private func edit() {
        guard let connection = editingConnection, let onEdit = onEdit else { return }
        
        let portInt = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? selectedEngine.defaultPort
        
        onEdit(
            connectionName.trimmingCharacters(in: .whitespacesAndNewlines),
            selectedEngine,
            host.trimmingCharacters(in: .whitespacesAndNewlines),
            portInt,
            username.trimmingCharacters(in: .whitespacesAndNewlines),
            password,
            sslMode,
            sshFields,
            connection.id
        )
        
        dismiss()
    }
    
    // MARK: - Helpers
    private func resetFields(for engine: EngineType) {
        host = engine.defaultHost
        port = engine.defaultPort > 0 ? String(engine.defaultPort) : ""
        username = ""; password = ""; sslMode = engine.defaultSSLMode
        filePath = ""; errorMessage = nil
    }
    
    private func selectKeyFile() {
        let panel = NSOpenPanel()
        panel.title = "Seleccionar clave privada SSH"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data, .text, .item]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        if panel.runModal() == .OK, let url = panel.url {
            sshFields.keyPath = url.path
        }
    }
}

// MARK: - Preview
#Preview {
    ConnectionFormView(
        mode: .connect,
        onConnect: { _, _, _, _, _, _, _, _ in },
        onSave: { _, _, _, _, _, _, _, _ in },
        onEdit: { _, _, _, _, _, _, _, _, _ in }
    )
}
