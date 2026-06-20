//
//  TableNodeView.swift
//  DBOtter
//
//  Created by AlexGI on 14/06/2026.
//

import SwiftUI

struct TableNodeView: View {
    let structure: TableStructure
    let isSelected: Bool
    let onDrag: (CGSize) -> Void
    let onTap: () -> Void
    let onDragEnded: (CGPoint) -> Void
    
    @State private var isHovered = false
    
    let nodeWidth: CGFloat = 220
    let rowHeight: CGFloat = 28
    let headerHeight: CGFloat = 36
    
    var body: some View {
        let dragGesture = DragGesture(minimumDistance: 4)
            .onChanged { value in onDrag(value.translation) }
            .onEnded { value in onDragEnded(value.location) }
        
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tablecells")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.accentColor)
                
                Text(structure.name)
                    .font(.system(.headline, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: headerHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .overlay(alignment: .bottom) {
                Divider().opacity(0.3)
            }
            
            // Columns
            ForEach(Array(structure.columns.enumerated()), id: \.offset) { index, column in
                ColumnRowInNode(column: column)
                    .frame(height: rowHeight)
                    .padding(.horizontal, 12)
                    .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                    .overlay(alignment: .bottom) {
                        if index < structure.columns.count - 1 {
                            Divider().opacity(0.15)
                        }
                    }
            }
        }
        .frame(width: nodeWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(
            color: .black.opacity(isSelected ? 0.25 : 0.15),
            radius: isSelected ? 16 : 8,
            x: 0,
            y: isSelected ? 8 : 4
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor.opacity(isHovered ? 0.4 : 0), lineWidth: 1)
        )
        .gesture(dragGesture)
        .onTapGesture(perform: onTap)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Centrar en esta tabla") {
                // Handled by parent via selection
            }
            Divider()
            Button("Ver estructura") {
                onTap()
            }
            Button("Ver datos") {
                // Could navigate to data tab
            }
        }
    }
}

struct ColumnRowInNode: View {
    let column: ColumnInfo
    
    private var typeIcon: String {
        let t = column.type.lowercased()
        switch true {
        case t.contains("int"): return "number"
        case t.contains("char") || t.contains("text"): return "textformat"
        case t.contains("bool"): return "checkmark.circle"
        case t.contains("date") || t.contains("time"): return "calendar"
        case t.contains("json"): return "curlybraces"
        case t.contains("uuid"): return "key"
        case t.contains("numeric") || t.contains("decimal") || t.contains("float"): return "percent"
        default: return "circle"
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // PK / FK indicator
            ZStack {
                if column.isPrimary {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.orange)
                        .help("Primary Key")
                } else if column.isFK {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.blue)
                        .help("Foreign Key")
                } else {
                    Image(systemName: typeIcon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
            .frame(width: 16)
            
            // Column name
            Text(column.name)
                .font(.system(.caption, design: .monospaced))
                .fontWeight(column.isPrimary ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer(minLength: 4)
            
            // Type badge
            Text(column.type)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
            
            // NOT NULL badge
            if !column.nullable {
                Text("NN")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .help("NOT NULL")
            }
        }
    }
}

#Preview {
    let sampleStructure = TableStructure(
        name: "users",
        columns: [
            ColumnInfo(name: "id", type: "bigint", nullable: false, defaultValue: "nextval('users_id_seq')", isPrimaryKey: true, isForeignKey: false, refTable: nil, refColumn: nil),
            ColumnInfo(name: "email", type: "varchar(255)", nullable: false, defaultValue: nil, isPrimaryKey: false, isForeignKey: false, refTable: nil, refColumn: nil),
            ColumnInfo(name: "name", type: "varchar(100)", nullable: true, defaultValue: nil, isPrimaryKey: false, isForeignKey: false, refTable: nil, refColumn: nil),
            ColumnInfo(name: "profile_id", type: "bigint", nullable: true, defaultValue: nil, isPrimaryKey: false, isForeignKey: true, refTable: "profiles", refColumn: "id"),
            ColumnInfo(name: "created_at", type: "timestamp with time zone", nullable: false, defaultValue: "now()", isPrimaryKey: false, isForeignKey: false, refTable: nil, refColumn: nil),
        ],
        indexes: [],
        foreignKeys: [
            ForeignKeyInfo(name: "users_profile_id_fkey", column: "profile_id", refTable: "profiles", refColumn: "id", onUpdate: "NO ACTION", onDelete: "NO ACTION")
        ]
    )
    
    VStack(spacing: 20) {
        TableNodeView(
            structure: sampleStructure,
            isSelected: false,
            onDrag: { _ in },
            onTap: {},
            onDragEnded: { _ in }
        )
        
        TableNodeView(
            structure: sampleStructure,
            isSelected: true,
            onDrag: { _ in },
            onTap: {},
            onDragEnded: { _ in }
        )
    }
    .padding()
    .background(Color(NSColor.windowBackgroundColor))
}