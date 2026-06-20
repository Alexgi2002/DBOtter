//
//  ToastManager.swift
//  DBOtter
//
//  Created by AlexGI on 14/06/2026.
//


import SwiftUI
import Foundation
import Combine

@MainActor
@Observable
class ToastManager {
    static let shared = ToastManager()
    
    var isShowing: Bool = false
    var message: String = ""
    var icon: String = "info.circle.fill"
    
    func show(message: String, icon: String = "flame.fill") {
        self.message = message
        self.icon = icon
        
        withAnimation(.spring()) {
            self.isShowing = true
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation(.spring()) {
                self.isShowing = false
            }
        }
    }
}
