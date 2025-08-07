import Foundation
import Combine

enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case unauthorized
    case serverError(Int)
    case decodingError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .invalidResponse:
            return "Invalid response"
        case .unauthorized:
            return "Unauthorized - check your API token"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}

class FlyAPIClient {
    private let baseURL = "https://api.machines.dev/v1"
    private let session = URLSession.shared
    
    
    // MARK: - App Management
    
    func getApp(appName: String, token: String) -> AnyPublisher<FlyApp, APIError> {
        Logger.log("Getting app: \(appName)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps/\(appName)") else {
            Logger.log("Invalid URL for app: \(appName)", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        Logger.log("GET \(url)", category: .network)
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.log("Invalid HTTP response for app", category: .network)
                    throw APIError.invalidResponse
                }
                
                Logger.log("App response: \(httpResponse.statusCode)", category: .network)
                
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.log("App response body: \(responseString)", category: .network)
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    Logger.log("Unauthorized for app", category: .network)
                    throw APIError.unauthorized
                case 404:
                    Logger.log("App not found: \(appName)", category: .network)
                    throw APIError.serverError(404)
                default:
                    Logger.log("App server error: \(httpResponse.statusCode)", category: .network)
                    throw APIError.serverError(httpResponse.statusCode)
                }
            }
            .decode(type: FlyApp.self, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                if error is DecodingError {
                    Logger.log("App decoding error: \(error)", category: .network)
                    return APIError.decodingError(error)
                }
                Logger.log("App network error: \(error)", category: .network)
                return APIError.invalidResponse
            }
            .eraseToAnyPublisher()
    }
    
    func createApp(request: FlyAppCreateRequest, token: String) -> AnyPublisher<FlyApp, APIError> {
        Logger.log("Creating app: \(request.appName) in org: \(request.orgSlug)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps") else {
            Logger.log("Invalid URL for app creation", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            urlRequest.httpBody = try encoder.encode(request)
            
            if let bodyString = String(data: urlRequest.httpBody!, encoding: .utf8) {
                Logger.log("POST \(url) with body: \(bodyString)", category: .network)
            }
        } catch {
            Logger.log("Failed to encode app creation request: \(error)", category: .network)
            return Fail(error: APIError.decodingError(error))
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.log("Invalid HTTP response for app creation", category: .network)
                    throw APIError.invalidResponse
                }
                
                Logger.log("App creation response: \(httpResponse.statusCode)", category: .network)
                
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.log("App creation response body: \(responseString)", category: .network)
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    Logger.log("Unauthorized for app creation", category: .network)
                    throw APIError.unauthorized
                default:
                    Logger.log("App creation server error: \(httpResponse.statusCode)", category: .network)
                    throw APIError.serverError(httpResponse.statusCode)
                }
            }
            .decode(type: FlyApp.self, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                if error is DecodingError {
                    Logger.log("App creation decoding error: \(error)", category: .network)
                    return APIError.decodingError(error)
                }
                Logger.log("App creation network error: \(error)", category: .network)
                return APIError.invalidResponse
            }
            .eraseToAnyPublisher()
    }
    
    // MARK: - Machine Management
    
    func launchMachine(appName: String, request: FlyLaunchRequest, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Starting machine launch for app: \(appName)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps/\(appName)/machines") else {
            Logger.log("Invalid URL for app: \(appName)", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            urlRequest.httpBody = try encoder.encode(request)
            
            if let bodyString = String(data: urlRequest.httpBody!, encoding: .utf8) {
                Logger.log("POST \(url) with body: \(bodyString)", category: .network)
            }
        } catch {
            Logger.log("Failed to encode request: \(error)", category: .network)
            return Fail(error: APIError.decodingError(error))
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.log("Invalid HTTP response", category: .network)
                    throw APIError.invalidResponse
                }
                
                Logger.log("Response status: \(httpResponse.statusCode)", category: .network)
                
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.log("Response body: \(responseString)", category: .network)
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    Logger.log("Unauthorized - check API token", category: .network)
                    throw APIError.unauthorized
                default:
                    Logger.log("Server error: \(httpResponse.statusCode)", category: .network)
                    throw APIError.serverError(httpResponse.statusCode)
                }
            }
            .decode(type: FlyMachine.self, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                if error is DecodingError {
                    Logger.log("Decoding error: \(error)", category: .network)
                    return APIError.decodingError(error)
                }
                Logger.log("Network error: \(error)", category: .network)
                return APIError.invalidResponse
            }
            .eraseToAnyPublisher()
    }
    
    func getMachine(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Getting machine status: \(machineId) for app: \(appName)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps/\(appName)/machines/\(machineId)") else {
            Logger.log("Invalid URL for machine: \(machineId)", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        Logger.log("GET \(url)", category: .network)
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.log("Invalid HTTP response for machine status", category: .network)
                    throw APIError.invalidResponse
                }
                
                Logger.log("Status response: \(httpResponse.statusCode)", category: .network)
                
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.log("Status response body: \(responseString)", category: .network)
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    Logger.log("Unauthorized for machine status", category: .network)
                    throw APIError.unauthorized
                default:
                    Logger.log("Status server error: \(httpResponse.statusCode)", category: .network)
                    throw APIError.serverError(httpResponse.statusCode)
                }
            }
            .decode(type: FlyMachine.self, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                if error is DecodingError {
                    Logger.log("Status decoding error: \(error)", category: .network)
                    return APIError.decodingError(error)
                }
                Logger.log("Status network error: \(error)", category: .network)
                return APIError.invalidResponse
            }
            .eraseToAnyPublisher()
    }
}