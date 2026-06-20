//
//  DisconnectedView.swift
//  DBOtter
//
//  Created by AlexGI on 17/06/2026.
//

import SwiftUI

struct DisconnectedView: View {
    @Binding var viewModel: TableDataViewModel
    
    var body: some View{
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Base de datos desconectada")
                .font(.title3).fontWeight(.semibold)
            if let msg = viewModel.errorMessage {
                Text(msg)
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            Text("Reconecta desde la barra lateral expandiendo la conexión para recargar esta tabla automáticamente.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
            Button(action: { Task { await viewModel.loadData() } }) {
                Label("Reintentar", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
