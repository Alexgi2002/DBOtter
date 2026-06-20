//
//  CoreManager.swift
//  DBOtter
//
//  Created by AlexGI on 12/06/2026.
//

import Foundation

@Observable
final class CoreManager {
    static let shared = CoreManager()
    
    var currentPort: Int? = nil
    var isEngineRunning = false
    var errorMessage: String? = nil
    
    private var goProcess: Process?
    private let outputPipe = Pipe()
    
    private init() {}
    
    func startEngine() {
        do {
            guard !isEngineRunning else { return }
            
            guard let binaryPath = Bundle.main.path(forResource: "core-engine", ofType: nil) else {
                print("❌ Binario no encontrado en bundle")
                return
            }
            
            print("🔍 Lanzando: \(binaryPath)")
            print("🔍 Existe: \(FileManager.default.fileExists(atPath: binaryPath))")
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            
            let fileHandle = outputPipe.fileHandleForReading
            fileHandle.waitForDataInBackgroundAndNotify()
            
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NSFileHandleDataAvailable,
                object: fileHandle,
                queue: nil
            ) { [weak self] _ in
                let data = fileHandle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("📤 GO STDOUT: \(output)")
                    self?.parseEngineOutput(output)
                }
                fileHandle.waitForDataInBackgroundAndNotify()
            }
            
            // Captura stderr
            let errHandle = process.standardError as! Pipe
            errHandle.fileHandleForReading.waitForDataInBackgroundAndNotify()
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name.NSFileHandleDataAvailable,
                object: errHandle.fileHandleForReading,
                queue: nil
            ) { _ in
                let data = errHandle.fileHandleForReading.availableData
                if let err = String(data: data, encoding: .utf8), !err.isEmpty {
                    print("📥 GO STDERR: \(err)")
                }
                errHandle.fileHandleForReading.waitForDataInBackgroundAndNotify()
            }
            
            process.currentDirectoryURL = URL(fileURLWithPath: (binaryPath as NSString).deletingLastPathComponent)
            try process.run()
            self.goProcess = process
            self.isEngineRunning = true
            print("🚀 Motor de Go lanzado con éxito (PID: \(process.processIdentifier))")
        } catch {
            print("❌ Error lanzando proceso: \(error)")
            print("❌ Error localized: \(error.localizedDescription)")
            self.errorMessage = "Fallo al arrancar: \(error)"
        }
    }
    
    func stopEngine() {
        goProcess?.terminate()
        isEngineRunning = false
        print("🛑 Motor de Go detenido.")
    }
    
    private func parseEngineOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("DBOtter_PORT:") {
                let portStr = line.replacingOccurrences(of: "DBOtter_PORT:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    self.currentPort = Int(portStr)
                    print("🔌 DBOtter conectado al puerto local de Go: \(portStr)")
                }
                break
            }
        }
    }
}