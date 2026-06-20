import SwiftUI
import Runestone

// Import Phase 3.1 - use existing CodeEditorViewModel
import CodeEditorViewModel

struct CodeEditorView: UIViewRepresentable {
    @ObservedObject var viewModel: CodeEditorViewModel
    
    func makeUIView(context: Context) -> some UIView {
        let textView = Runestone.TextView()
        textView.delegate = context.coordinator
        textView.text = viewModel.text
        return textView
    }
    
    func updateUIView(_ uiView: some UIView, context: Context) {
        if let textView = uiView as? Runestone.TextView {
            textView.text = viewModel.text
            textView.selectedRange = NSRange(location: viewModel.text.count, length: 0)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, Runestone.TextViewDelegate {
        let parent: CodeEditorView
        
        init(_ parent: CodeEditorView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: Runestone.TextView) {
            parent.viewModel.text = textView.text
        }
    }
}