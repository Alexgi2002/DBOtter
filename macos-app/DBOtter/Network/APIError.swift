//
//  APIError.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(String)
    case encodingError(String)
    case networkError(Error)
    case serverError(String)
    case noData
    case timeout
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL inválida"
        case .invalidResponse:
            return "Respuesta inválida del servidor"
        case .httpError(let statusCode, let message):
            return "Error HTTP \(statusCode): \(message ?? "Sin detalles")"
        case .decodingError(let msg):
            return "Error decodificando: \(msg)"
        case .encodingError(let msg):
            return "Error codificando: \(msg)"
        case .networkError(let error):
            return "Error de red: \(error.localizedDescription)"
        case .serverError(let msg):
            return "Error del servidor: \(msg)"
        case .noData:
            return "El servidor no devolvió datos"
        case .timeout:
            return "Tiempo de espera agotado"
        case .cancelled:
            return "Petición cancelada"
        }
    }
    
    var isConnectionError: Bool {
        switch self {
        case .networkError, .timeout, .invalidURL, .serverError:
            return true
        case .httpError(let code, _):
            return code == 503 || code == 502
        default:
            return false
        }
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.noData, .noData),
             (.timeout, .timeout),
             (.cancelled, .cancelled):
            return true
        case (.httpError(let lhsCode, let lhsMsg), .httpError(let rhsCode, let rhsMsg)):
            return lhsCode == rhsCode && lhsMsg == rhsMsg
        case (.decodingError(let lhsMsg), .decodingError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.encodingError(let lhsMsg), .encodingError(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.networkError(let lhsErr), .networkError(let rhsErr)):
            return lhsErr.localizedDescription == rhsErr.localizedDescription
        case (.serverError(let lhsMsg), .serverError(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}