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
    
    func launchMachine(appName: String, request: FlyLaunchRequest, token: String) -> AnyPublisher<FlyMachine, APIError> {
        guard let url = URL(string: "\(baseURL)/apps/\(appName)/machines") else {
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            return Fail(error: APIError.decodingError(error))
                .eraseToAnyPublisher()
        }
        
        return session.dataTaskPublisher(for: urlRequest)
            .map(\.data)
            .decode(type: FlyMachine.self, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if error is DecodingError {
                    return APIError.decodingError(error)
                }
                return APIError.invalidResponse
            }
            .eraseToAnyPublisher()
    }
    
    func getMachine(appName: String, machineId: String, token: String) -> AnyPublisher<FlyMachine, APIError> {
        guard let url = URL(string: "\(baseURL)/apps/\(appName)/machines/\(machineId)") else {
            return Fail(error: APIError.invalidURL)
                .eraseToAnyPublisher()
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        return session.dataTaskPublisher(for: urlRequest)
            .tryMap { data, response -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401:
                    throw APIError.unauthorized
                default:
                    throw APIError.serverError(httpResponse.statusCode)
                }
            }
            .decode(type: FlyMachine.self, decoder: JSONDecoder())
            .mapError { error -> APIError in
                if let apiError = error as? APIError {
                    return apiError
                }
                if error is DecodingError {
                    return APIError.decodingError(error)
                }
                return APIError.invalidResponse
            }
            .eraseToAnyPublisher()
    }
}