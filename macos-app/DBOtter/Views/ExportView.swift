//
//  ExportView.swift
//  DBOtter
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ExportView: View {
    let tableName: String
    
    @State private var format: ExportFormat = .csv
    @State private var includeHeader = true
    @State private var isExporting = false
    @Environment(\.dismiss) private var dismiss
    
    private let databaseService = DatabaseService.shared
    private let toast = ToastManager.shared
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case xlsx = "Excel (xlsx)"
        
        var fileExtension: String { self == .csv ? "csv" : "xlsx" }
        var formatKey: String { self == .csv ? "csv" : "xlsx" }
        var icon: String { self == .csv ? "doc.plaintext" : "tablecells" }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Exportar tabla", systemImage: "square.and.arrow.up")
                    .font(.headline)
                Spacer()
                Button("Cancelar") { dismiss() }
            }
            
            Divider()
            
            Text("Tabla: \(tableName)")
                .foregroundColor(.secondary)
//                .font(.subheadline)
            
            Picker("Formato", selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { f in
                    Label(f.rawValue, systemImage: f.icon).tag(f)
                }
            }
            .pickerStyle(.radioGroup)
            
            Toggle("Incluir encabezados", isOn: $includeHeader)
            
            Spacer()
            
            Button(action: exportTable) {
                if isExporting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Exportando...")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label("Exportar", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
        .padding(30)
        .frame(width: 320, height: 260)
    }
    
    private func exportTable() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(tableName).\(format.fileExtension)"
        panel.allowedContentTypes = format == .csv
            ? [.commaSeparatedText]
            : [.init(filenameExtension: "xlsx")!]
        
        guard panel.runModal() == .OK, let url = panel.url else { return }
        
        isExporting = true
        
        Task {
            do {
                let options = ExportOptions(
                    tableName: tableName,
                    format: format.formatKey,
                    columns: nil,
                    limit: nil,
                    offset: nil,
                    search: nil,
                    sortBy: nil,
                    sortDesc: nil,
                    whereClause: nil,
                    delimiter: nil,
                    quoteChar: nil,
                    encoding: nil,
                    sheetName: nil,
                    freezePanes: format == .xlsx ? true : nil,
                    autoWidth: format == .xlsx ? true : nil,
                    headerBold: format == .xlsx ? true : nil,
                    includeHeader: includeHeader,
                    includeTypes: nil,
                    includeTimestamp: nil,
                    includeStats: nil
                )
                
                let data = try await databaseService.exportTable(options)
                try data.write(to: url)
                
                dismiss()
                toast.show(message: "Exportado: \(url.lastPathComponent)", icon: "checkmark.circle.fill")
            } catch {
                toast.show(message: "Error al exportar: \(error.localizedDescription)", icon: "xmark.circle.fill")
            }
            isExporting = false
        }
    }
}
