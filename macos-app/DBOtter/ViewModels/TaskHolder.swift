final class TaskHolder {
    var task: Task<Void, Never>?
    
    deinit {
        task?.cancel() // Es seguro porque TaskHolder no es @MainActor
    }
}