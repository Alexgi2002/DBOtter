//
//  TaskHolder.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//


final class TaskHolder {
    var task: Task<Void, Never>?
    
    deinit {
        task?.cancel()
    }
}
