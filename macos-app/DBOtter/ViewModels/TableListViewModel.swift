//
//  TableListViewModel.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

@MainActor
@Observable
final class TableListViewModel {
    var tables: [TableEntity] = []
    var isLoading = false
    var errorMessage: String?
    var searchText = ""
     
    // MARK: - Dependencies
    
    private let databaseService = DatabaseService.shared
    
    // MARK: - Computed
    
    var filteredTables: [TableEntity] {
        if searchText.isEmpty {
            return tables
        }
        return tables.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    // MARK: - Public Methods
    
    func loadTables() async {
        isLoading = true
        errorMessage = nil
        
        do {
            tables = try await databaseService.fetchTables()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Error: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    func refresh() async {
        await loadTables()
    }
}
