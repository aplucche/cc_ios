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
    
    // MARK: - Generic API Request Handler
    
    private func performRequest<T: Codable>(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        token: String,
        responseType: T.Type,
        operationName: String
    ) -> AnyPublisher<T, APIError> {
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        if method != "GET" {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        if let body = body {
            urlRequest.httpBody = body
            if let bodyString = String(data: body, encoding: .utf8) {
                Logger.log("\(method) \(url) with body: \(bodyString)", category: .network)
            }
        } else {
            Logger.log("\(method) \(url)", category: .network)
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.log("Invalid HTTP response for \(operationName)", category: .network)
                    throw APIError.invalidResponse
                }
                
                Logger.log("\(operationName) response: \(httpResponse.statusCode)", category: .network)
                
                if let responseString = String(data: data, encoding: .utf8) {
                    Logger.log("\(operationName) response body: \(responseString)", category: .network)
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    Logger.log("Unauthorized for \(operationName)", category: .network)
                    throw APIError.unauthorized
                case 404:
                    Logger.log("\(operationName) not found (404)", category: .network)
                    throw APIError.serverError(404)
                default:
                    Logger.log("\(operationName) server error: \(httpResponse.statusCode)", category: .network)
                    throw APIError.serverError(httpResponse.statusCode)
                }
            }
            .decode(type: responseType, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                if error is DecodingError {
                    Logger.log("\(operationName) decoding error: \(error)", category: .network)
                    return APIError.decodingError(error)
                }
                Logger.log("\(operationName) network error: \(error)", category: .network)
                return APIError.invalidResponse
            }
            .share()
            .eraseToAnyPublisher()
    }
    
    // MARK: - App Management
    
    func getApp(appName: String, token: String) -> AnyPublisher<FlyApp, APIError> {
        Logger.log("Getting app: \(appName)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps/\(appName)") else {
            Logger.log("Invalid URL for app: \(appName)", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        return performRequest(
            url: url,
            method: "GET",
            token: token,
            responseType: FlyApp.self,
            operationName: "Get app"
        )
    }
    
    func createApp(request: FlyAppCreateRequest, token: String) -> AnyPublisher<FlyApp, APIError> {
        Logger.log("Creating app: \(request.appName) in org: \(request.orgSlug)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps") else {
            Logger.log("Invalid URL for app creation", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let body = try encoder.encode(request)
            
            return performRequest(
                url: url,
                method: "POST",
                body: body,
                token: token,
                responseType: FlyAppCreateResponse.self,
                operationName: "App creation"
            )
            .flatMap { [weak self] createResponse -> AnyPublisher<FlyApp, APIError> in
                Logger.log("App created with id: \(createResponse.id), fetching full details", category: .network)
                guard let self = self else {
                    return Fail(error: APIError.invalidResponse).eraseToAnyPublisher()
                }
                // Fetch the full app details using the app name
                return self.getApp(appName: request.appName, token: token)
            }
            .share()
            .eraseToAnyPublisher()
        } catch {
            Logger.log("Failed to encode app creation request: \(error)", category: .network)
            return Fail(error: APIError.decodingError(error))
                .eraseToAnyPublisher()
        }
    }
    
    // MARK: - Machine Management
    
    func launchMachine(appName: String, request: FlyLaunchRequest, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Starting machine launch for app: \(appName)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps/\(appName)/machines") else {
            Logger.log("Invalid URL for app: \(appName)", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let body = try encoder.encode(request)
            
            return performRequest(
                url: url,
                method: "POST",
                body: body,
                token: token,
                responseType: FlyMachine.self,
                operationName: "Machine launch"
            )
        } catch {
            Logger.log("Failed to encode request: \(error)", category: .network)
            return Fail(error: APIError.decodingError(error))
                .eraseToAnyPublisher()
        }
    }
    
    func getMachine(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        Logger.log("Getting machine status: \(machineId) for app: \(appName)", category: .network)
        
        guard let url = URL(string: "\(baseURL)/apps/\(appName)/machines/\(machineId)") else {
            Logger.log("Invalid URL for machine: \(machineId)", category: .network)
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        return performRequest(
            url: url,
            method: "GET",
            token: token,
            responseType: FlyMachine.self,
            operationName: "Machine status"
        )
    }
}