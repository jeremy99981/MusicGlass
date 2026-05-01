import Foundation

protocol HTTPClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> Data
    func decoded<T: Decodable>(_ type: T.Type, for request: URLRequest, decoder: JSONDecoder) async throws -> T
}

struct HTTPClient: HTTPClientProtocol {
    private let session: URLSession
    private let logger: NetworkLogger

    init(session: URLSession = .shared, logger: NetworkLogger = NetworkLogger()) {
        self.session = session
        self.logger = logger
    }

    func data(for request: URLRequest) async throws -> Data {
        do {
            logger.logRequest(request)
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            logger.logResponse(httpResponse, bytes: data.count)
            guard (200..<300).contains(httpResponse.statusCode) else {
                throw NetworkError.httpStatus(httpResponse.statusCode, data)
            }
            return data
        } catch let error as NetworkError {
            throw error
        } catch is CancellationError {
            throw AppError.cancelled
        } catch {
            throw NetworkError.transport(error)
        }
    }

    func decoded<T: Decodable>(_ type: T.Type, for request: URLRequest, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let data = try await data(for: request)
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }
}
