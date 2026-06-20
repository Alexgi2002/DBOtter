//
//  DBOtterApp.swift
//  DBOtter
//
//  Created by AlexGI on 12/06/2026.
//

import SwiftUI
import SwiftData

@main
struct DBOtterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var toastManager = ToastManager.shared
    
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            SavedConnection.self,
            PersistedTab.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            do {
            // Migración fallida — destruir store y arrancar limpio
                let storeURL = modelConfiguration.url
                
                try? FileManager.default.removeItem(at: storeURL)
                let shmURL = storeURL.appendingPathExtension("-shm")
                let walURL = storeURL.appendingPathExtension("-wal")
                try? FileManager.default.removeItem(at: shmURL)
                try? FileManager.default.removeItem(at: walURL)
            
            
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainView()
                .withGlobalToast()
                .environment(toastManager)
        }
        .windowStyle(.hiddenTitleBar)
        .modelContainer(Self.sharedModelContainer)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        CoreManager.shared.stopEngine()
    }
}
