struct GlobalToastModifier: ViewModifier {
    @Environment(ToastManager.self) private var toastManager
    
    func body(content: Content) -> some View {
        ZStack {
            content // Aquí se renderiza toda tu app normal (TabView, Login, etc.)
            
            // Capa superior: El Toast Flotante Global
            if toastManager.isShowing {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: toastManager.icon)
                            .foregroundColor(.hotPink)
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

// Extensión para llamarlo de forma limpia (.withGlobalToast())
extension View {
    func withGlobalToast() -> some View {
        self.modifier(GlobalToastModifier())
    }
}