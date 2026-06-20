//
//  Endpoint.swift
//  DBOtter
//
//  Created by AlexGI on 13/06/2026.
//

import Foundation

protocol Endpoint {
    var baseURL: URL { get }
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem]? { get }
    var body: Encodable? { get }
    var timeout: TimeInterval { get }
}

extension Endpoint {
    var headers: [String: String] {
        ["Content-Type": "application/json"]
    }
    
    var queryItems: [URLQueryItem]? { nil }
    var body: Encodable? { nil }
    var timeout: TimeInterval { 30 }
}

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case DELETE = "DELETE"
    case PATCH = "PATCH"
}

extension Endpoint {
    func makeRequest(encoder: JSONEncoder = JSONEncoder()) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        
        guard let url = components?.url else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = try encoder.encode(body)
        }
        
        return request
    }
}