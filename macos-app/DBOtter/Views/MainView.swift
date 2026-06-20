//
//  MainView.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import SwiftUI
import SwiftData

extension Notification.Name {
    static let connectionReconnected = Notification.Name("DBOtter.connectionReconnected")
}

// Diagram mode - replaces tabbed interface when viewing full DB diagram
struct DiagramModeView: View {
    let connectionId: UUID
    let dbName: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Diagram header with close button
            HStack {
                Text("Diagrama: \(dbName)")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cerrar diagrama y volver a pestañas")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            // Full diagram view
            TableDiagramView(tableName: "", connectionId: connectionId)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct MainView: View {
    @State private var openTabs: [TableTab] = []
    @State private var activeTabId: UUID? = nil

    // Diagram mode state
    @State private var diagramConnectionId: UUID? = nil
    @State private var diagramDbName: String = ""

    private var activeTab: TableTab? {
        openTabs.first { $0.id == activeTabId }
    }

    private var isInDiagramMode: Bool {
        diagramConnectionId != nil
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationSplitView {
            SidebarView(
                onOpenTable: openOrFocusTab,
                onOpenDiagram: { connectionId, dbName in
                    // Switch to diagram mode - replaces tabbed interface
                    diagramConnectionId = connectionId
                    diagramDbName = dbName
                },
                onReconnected: notifyReconnected
            )
        } detail: {
            detailView
        }
        .padding(.bottom, 4)
        .padding(.leading, 4)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerView
        }
        .task {
            CoreManager.shared.startEngine()
            loadPersistedTabs()
        }
    }

    // MARK: - Persistence

    private func loadPersistedTabs() {
        guard let persisted = try? db.fetchTabs(), !persisted.isEmpty else { return }
        openTabs = persisted.map { TableTab(from: $0) }
        activeTabId = persisted.first(where: { $0.isActive })?.id ?? openTabs.first?.id
    }

    private func persistTabs() {
        let snapshot = openTabs.enumerated().map { (index, tab) in
            (tab: tab, order: index, isActive: tab.id == activeTabId)
        }
        try? db.saveTabs(snapshot: snapshot)
    }

    // MARK: - Tab Management

    private func openOrFocusTab(tableName: String, connectionId: UUID, dbName: String, connectionName: String) {
        if let existing = openTabs.first(where: {
            $0.tableName == tableName && $0.connectionId == connectionId && $0.dbName == dbName
        }) {
            activeTabId = existing.id
        } else {
            let tab = TableTab(tableName: tableName, connectionId: connectionId, dbName: dbName, connectionName: connectionName)
            openTabs.append(tab)
            activeTabId = tab.id
        }
        persistTabs()
    }

    private func closeTab(_ tab: TableTab) {
        guard let idx = openTabs.firstIndex(of: tab) else { return }
        openTabs.remove(at: idx)
        if activeTabId == tab.id {
            activeTabId = openTabs.isEmpty ? nil : openTabs[max(0, idx - 1)].id
        }
        persistTabs()
    }

    private func notifyReconnected(connectionId: UUID) {
        NotificationCenter.default.post(
            name: .connectionReconnected,
            object: nil,
            userInfo: ["connectionId": connectionId]
        )
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        if isInDiagramMode, let connectionId = diagramConnectionId {
            // Full-screen diagram mode - no tabbar, no tabs
            DiagramModeView(
                connectionId: connectionId,
                dbName: diagramDbName,
                onClose: { exitDiagramMode() }
            )
        } else {
            // Regular tabbed table interface
            VStack(spacing: 0) {
                if !openTabs.isEmpty {
                    tabBar
                }
                Group {
                    if let tab = activeTab {
                        TableDataView(tableName: tab.tableName, connectionId: tab.connectionId, dbName: tab.dbName)
                            .id(tab.id)
                    } else {
                        emptyDetailView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func exitDiagramMode() {
        diagramConnectionId = nil
        diagramDbName = ""
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack{
            Button(action: { changeTab(forward: false) }) {
                Image(systemName: "chevron.left")
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .help("Pestaña anterior (⌘←)")
            .padding(.horizontal, 8)
            
            Button(action: { changeTab(forward: true) }) {
                Image(systemName: "chevron.right")
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .help("Pestaña siguiente (⌘→)")
            .padding(.horizontal, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    
                    ForEach(openTabs) { tab in
                        tabItem(tab)
                            .contextMenu{
                                Button("Cerrar pestaña", action: {
                                    closeTab(tab)
                                })
                                Button("Cerrar otras pestañas", action: {
                                    for tab2 in openTabs {
                                        if tab.id != tab2.id {
                                            closeTab(tab2)
                                        }
                                    }
                                })
                                Button("Cerrar todas las pestañas", action: {
                                    for tab in openTabs {
                                        closeTab(tab)
                                    }
                                })
                            }
                    }
                }
            }
        }
        .frame(height: 36)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider() }
    }
    
    private func changeTab(forward: Bool) {
        if let index = openTabs.firstIndex(where: { $0.id == activeTabId }) {
            if forward {
                activeTabId = openTabs[(index + 1) % openTabs.count].id
            } else {
                activeTabId = openTabs[(index - 1 + openTabs.count) % openTabs.count].id
            }
        }
    }

    private func tabItem(_ tab: TableTab) -> some View {
        let isActive = tab.id == activeTabId
        return Button(action: { activeTabId = tab.id; persistTabs() }) {
            HStack(spacing: 6) {
                Image(systemName: "tablecells")
//                    .font(.caption2)
                    .font(.system(size: 16))
                    .foregroundStyle(isActive ? .primary : .secondary)
                Text(tab.tableName)
//                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
                Button(action: { closeTab(tab) }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(2)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(isActive ? Color(NSColor.windowBackgroundColor) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle().fill(Color.accentColor).frame(height: 2)
            }
        }
        .overlay(alignment: .trailing) {
            Divider().frame(height: 20)
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if let tab = activeTab {
                HStack(spacing: 4) {
                    Text(tab.connectionName).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(tab.dbName).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    Text(tab.tableName).foregroundStyle(.primary)
                }
                .font(.caption)
                .lineLimit(1)
            } else {
                Text("Sin tabla seleccionada")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text("v\(appVersion)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Empty State

    private var emptyDetailView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tablecells")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("DBOtter")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Selecciona una tabla de la barra lateral")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                Text("Las conexiones guardadas aparecen como carpetas en la barra lateral.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                Text("Haz clic en una conexión para expandirla y ver sus tablas.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 300)
            .padding(.horizontal)

//            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    MainView()
        .frame(width: 1200, height: 800)
}
