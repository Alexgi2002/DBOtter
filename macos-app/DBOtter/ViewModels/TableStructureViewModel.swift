//
//  TableStructureViewModel.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

@MainActor
@Observable
final class TableStructureViewModel {
    var structure: TableStructure?
    var isLoading = false
    var errorMessage: String?
    
    // MARK: - Private
    
    private let tableName: String
    private let databaseService = DatabaseService.shared
    private let taskHolder = TaskHolder()
    
    init(tableName: String) {
        self.tableName = tableName
    }
    
    // MARK: - Public Methods
    
    func loadStructure() async {
        taskHolder.task?.cancel()
        
        taskHolder.task = Task {
            await performLoad()
        }
        
        await taskHolder.task?.value
    }
    
    func refresh() {
        Task { await loadStructure() }
    }
    
    // MARK: - Private Methods
    
    private func performLoad() async {
        guard !Task.isCancelled else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let structure = try await databaseService.fetchTableStructure(table: tableName, schema: "public")
            
            guard !Task.isCancelled else { return }
            
            self.structure = structure
            
        } catch let error as APIError {
            guard !Task.isCancelled else { return }
            errorMessage = error.errorDescription
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}
