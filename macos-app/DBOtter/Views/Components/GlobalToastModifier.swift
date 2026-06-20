//
//  GlobalToastModifier.swift
//  DBOtter
//
//  Created by AlexGI on 14/06/2026.
//

import SwiftUI

struct GlobalToastModifier: ViewModifier {
    @Environment(ToastManager.self) private var toastManager
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if toastManager.isShowing {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: toastManager.icon)
                            .foregroundColor(.blue)
                        Text(toastManager.message)
                            .bold()
                            .foregroundColor(.white)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 24)
                    .background(Color(white: 0.15))
                    .clipShape(Capsule())
                    .shadow(radius: 10, y: 5)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    
                    Spacer()
                }
                .padding(.top, 20)
                .zIndex(1) // Asegura que quede por encima de todo el árbol visual
            }
        }
    }
}

extension View {
    func withGlobalToast() -> some View {
        self.modifier(GlobalToastModifier())
    }
}
