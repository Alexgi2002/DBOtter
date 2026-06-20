import SwiftUI

@MainActor
@Observable
class ToastManager {
    // Instancia compartida por comodidad o inyección
    static let shared = ToastManager()
    
    var isShowing: Bool = false
    var message: String = ""
    var icon: String = "info.circle.fill"
    
    func show(message: String, icon: String = "flame.fill") {
        self.message = message
        self.icon = icon
        
        // Evitamos solapamientos si ya hay uno en pantalla
        withAnimation(.spring()) {
            self.isShowing = true
        }
        
        // Auto-hide automático cooperativo
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.spring()) {
                self.isShowing = false
            }
        }
    }
}