//
//  TableStructureView.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import SwiftUI

struct TableStructureView: View {
    @State private var viewModel: TableStructureViewModel
    let tableName: String

    init(tableName: String) {
        self.tableName = tableName
        self.viewModel = TableStructureViewModel(tableName: tableName)
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                ProgressView("Cargando estructura...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let structure = viewModel.structure {
                structureContent(structure)
            } else if let error = viewModel.errorMessage {
                ErrorView(message: error) { Task { await viewModel.loadStructure() } }
            } else {
                ContentUnavailableView("Sin estructura", systemImage: "tablecells.badge.ellipsis",
                    description: Text("No se pudo cargar la estructura"))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task { await viewModel.loadStructure() }
    }

    @ViewBuilder
    private func structureContent(_ structure: TableStructure) -> some View {
        ScrollView {
            columnsGrid(structure.columns)
            .padding(20)
        }
    }


    private func columnsGrid(_ columns: [ColumnInfo]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                colHeader("Columna (\(columns.count))", width: 230)
                colHeader("Tipo", width: nil)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            ForEach(Array(columns.enumerated()), id: \.offset) { idx, col in
                HStack(spacing: 0) {
                    Text(col.name)
//                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: 220, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)

                    Divider().frame(height: 28)

                    Text(col.type)
//                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                }
                .background(idx % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.4))
                .overlay(alignment: .bottom) { Divider().opacity(0.2) }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }

    // MARK: - Indexes Grid

    private func indexesGrid(_ indexes: [IndexInfo]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                colHeader("Nombre", width: 200)
                colHeader("Columnas", width: nil)
                colHeader("Tipo", width: 90)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            ForEach(Array(indexes.enumerated()), id: \.offset) { idx, index in
                HStack(spacing: 0) {
                    Text(index.name)
//                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: 200, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                    Divider().frame(height: 28)
                    Text(index.columns.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                    Divider().frame(height: 28)
                    HStack(spacing: 4) {
                        if index.primary { badge("PRIMARY", .orange) }
                        else if index.unique { badge("UNIQUE", .green) }
                        else { badge("INDEX", .secondary) }
                    }
                    .frame(width: 90, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                }
                .background(idx % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.4))
                .overlay(alignment: .bottom) { Divider().opacity(0.2) }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }

    // MARK: - Foreign Keys Grid

    private func foreignKeysGrid(_ fks: [ForeignKeyInfo]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                colHeader("Columna", width: 150)
                colHeader("Referencia", width: nil)
                colHeader("ON UPDATE", width: 110)
                colHeader("ON DELETE", width: 110)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider() }

            ForEach(Array(fks.enumerated()), id: \.offset) { idx, fk in
                HStack(spacing: 0) {
                    Text(fk.column)
//                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                    Divider().frame(height: 28)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                        Text("\(fk.refTable).\(fk.refColumn)")
                            .font(.system(.caption, design: .monospaced)).foregroundStyle(.blue).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    Divider().frame(height: 28)
                    Text(fk.onUpdate)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                    Divider().frame(height: 28)
                    Text(fk.onDelete)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                }
                .background(idx % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.4))
                .overlay(alignment: .bottom) { Divider().opacity(0.2) }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
    }

    // MARK: - Helpers

    private func colHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title)
//            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(minWidth: width, maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

#Preview {
    TableStructureView(tableName: "users")
        .frame(width: 700, height: 500)
}
