//
//  CoreManager.swift
//  DBOtter
//
//  Created by AlexGI on 12/06/2026.
//

import Foundation

@Observable
class CoreManager {
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
            process.standardError = Pipe()  // Captura stderr
            
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
    
    /// Lanza el binario de Go que está empaquetado dentro de la app de Mac
//    func startEngine() {
//        do {
//        guard !isEngineRunning else { return }
//        
//        guard let binaryPath = Bundle.main.path(forResource: "core-engine", ofType: nil) else {
//            print("No se encontró el binario del motor de Go en el bundle.")
//            self.errorMessage = "No se encontró el binario del motor de Go en el bundle."
//            return
//        }
//        
//        let process = Process()
//        process.executableURL = URL(fileURLWithPath: binaryPath)
//        process.standardOutput = outputPipe
//        
//        // 2. Capturar el stdout para leer el puerto dinámico
//        let fileHandle = outputPipe.fileHandleForReading
//        fileHandle.waitForDataInBackgroundAndNotify()
//        
//        NotificationCenter.default.addObserver(
//            forName: NSNotification.Name.NSFileHandleDataAvailable,
//            object: fileHandle,
//            queue: nil
//        ) { [weak self] _ in
//            let data = fileHandle.availableData
//            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
//                self?.parseEngineOutput(output)
//            }
//            fileHandle.waitForDataInBackgroundAndNotify()
//        }
//        
//        // 3. Lanzar el proceso
//            process.currentDirectoryURL = URL(fileURLWithPath: (binaryPath as NSString).deletingLastPathComponent)
//            try process.run()
//            self.goProcess = process
//            self.isEngineRunning = true
//            print("🚀 Motor de Go lanzado con éxito.")
//        } catch {
//            print(error.localizedDescription)
//            self.errorMessage = "Fallo al arrancar el motor: \(error.localizedDescription)"
//        }
//    }
    
    /// Detiene el proceso de Go al cerrar la app
    func stopEngine() {
        goProcess?.terminate()
        isEngineRunning = false
        print("🛑 Motor de Go detenido.")
    }
    
    /// Analiza la salida de Go para extraer el puerto: "DBOtter_PORT:XXXXX"
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
    
    // ---- PETICIONES HTTP AL CORE DE GO ----
    
    /// Envía la solicitud de conexión al motor de Go
    func connectToDatabase(engine: String, connString: String) async -> Bool {
        guard let port = currentPort else { return false }
        guard let url = URL(string: "http://127.0.0.1:\(port)/connect") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["engine": engine, "conn_string": connString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            print("❌ Error de red conectando al core: \(error)")
        }
        return false
    }
    
    /// Obtiene los datos de una tabla con paginación
    func fetchTableData(tableName: String, limit: Int = 100, offset: Int = 0) async -> QueryResult? {
        guard let port = currentPort else { return nil }
        var components = URLComponents(string: "http://127.0.0.1:\(port)/table-data")!
        components.queryItems = [
            URLQueryItem(name: "table", value: tableName),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components.url else { return nil }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return try JSONDecoder().decode(QueryResult.self, from: data)
            } else {
                print("❌ Error HTTP: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                if let errorStr = String(data: data, encoding: .utf8) {
                    print("❌ Error body: \(errorStr)")
                }
            }
        } catch {
            print("❌ Error obteniendo datos de tabla: \(error)")
        }
        return nil
    }
}

// MARK: - Modelos compartidos con Go

struct QueryResult: Codable {
    let columns: [String]
    let rows: [[JSONValue]]
}

// JSONValue para manejar cualquier tipo JSON (String, Int, Double, Bool, Null)
enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let v = try? container.decode(String.self) {
            self = .string(v)
        } else if let v = try? container.decode(Int.self) {
            self = .int(v)
        } else if let v = try? container.decode(Double.self) {
            self = .double(v)
        } else if let v = try? container.decode(Bool.self) {
            self = .bool(v)
        } else {
            self = .null
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v): try container.encode(v)
        case .double(let v): try container.encode(v)
        case .bool(let v): try container.encode(v)
        case .null: try container.encodeNil()
        }
    }
    
    var displayString: String {
        switch self {
        case .string(let v): return v
        case .int(let v): return String(v)
        case .double(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .null: return "NULL"
        }
    }
}
