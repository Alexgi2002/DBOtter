//
//  APIClient.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

final class APIClient {
    static let shared = APIClient()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    
    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        
        self.session = URLSession(configuration: configuration)
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .useDefaultKeys
        
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }
    
    // MARK: - Generic Request
    
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let request: URLRequest
        do {
            request = try endpoint.makeRequest(encoder: encoder)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            try validateResponse(httpResponse, data: data)
            
            if data.isEmpty {
                throw APIError.noData
            }
            
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if text?.isEmpty == true {
                throw APIError.noData
            }
            
            let rawBody = String(data: data, encoding: .utf8) ?? "<binary>"
            print("[API] status=\(httpResponse.statusCode) url=\(request.url?.absoluteString ?? "<nil>") body=\(rawBody)")

            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                print("[API] decode error for \(T.self): \(error)")
                print("[API] raw body preview: \(rawBody)")
                throw APIError.decodingError(error.localizedDescription)
            }
            
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    func requestVoid(_ endpoint: Endpoint) async throws {
        let request: URLRequest
        do {
            request = try endpoint.makeRequest(encoder: encoder)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }
        
        do {
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            try validateResponse(httpResponse, data: Data())
            
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            throw mapURLError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Helpers
    
    private func validateResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 400:
            let message = decodeErrorMessage(from: data)
            throw APIError.httpError(statusCode: 400, message: message)
        case 401:
            throw APIError.httpError(statusCode: 401, message: "No autorizado")
        case 403:
            throw APIError.httpError(statusCode: 403, message: "Prohibido")
        case 404:
            throw APIError.httpError(statusCode: 404, message: "No encontrado")
        case 500...599:
            let message = decodeErrorMessage(from: data)
            throw APIError.serverError(message ?? "Error interno del servidor")
        default:
            let message = decodeErrorMessage(from: data)
            throw APIError.httpError(statusCode: response.statusCode, message: message)
        }
    }
    
    private func decodeErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = json["error"] as? String ?? json["message"] as? String ?? json["detail"] as? String {
            return message
        }

        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }
    
    private func mapURLError(_ error: URLError) -> APIError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost:
            return .networkError(error)
        default:
            return .networkError(error)
        }
    }
}