// Custom Dynamic Table View for DBOtter
// This view handles tables with many columns efficiently while taking up full available space

import SwiftUI

struct DynamicTableView: View {
    let data: [[String]]
    let columns: [String]
    
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(columns.enumerated(), id: \.offset) { index, columnName in
                    VStack {
                        // Column header
                        VStack(alignment: .leading, spacing: 0) {
                            Text(columnName)
//                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color(NSColor.controlBackgroundColor))
                            
                            Divider()
                        }
                        .frame(minHeight: 40)
                        
                        // Column content
                        LazyVStack(alignment: .leading, spacing: 0,) {
                            ForEach(data, id: \.self.hashValue) { row in
                                if index < row.count {
//                                    Text(String(describing: row[index]) ?? "")
                                    Text(row[index])
//                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            rowBackgroundColor(for: row[index])
                                        )
//                                        .overlay(
//                                            Rectangle()
//                                                .fill(Color.green.opacity(0.1))
//                                                .frame(height: 1)
//                                                .offset(y:20)
//                                        )
                                }
                                
                                Divider()
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(minWidth: 200, maxWidth: .infinity)
                    .background(Color(NSColor.windowBackgroundColor))
                    .overlay(
                        Rectangle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            .offset(y: 0)
                    )
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
//        .overlay(
//            RoundedRectangle(cornerRadius: 8)
//                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
//        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // Función auxiliar para calcular el color sin saturar el compilador
    private func rowBackgroundColor(for value: String) -> Color {
        if value == "NULL" {
            return Color(NSColor.controlBackgroundColor).opacity(0.5)
        } else {
            return Color.clear
        }
    }

}
