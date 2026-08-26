import Foundation

public class CanvasAPIClient {
    private let baseURL: URL
    private let tokenProvider: () -> String?
    private let session: URLSession
    
    public init(baseURL: URL, session: URLSession = .shared, tokenProvider: @escaping () -> String?) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
    }
    
    private func makeRequest(path: String) throws -> URLRequest {
        guard let token = tokenProvider() else {
            throw URLError(.userAuthenticationRequired)
        }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    
    public func getCourses() async throws -> [CanvasCourseDTO] {
        let request = try makeRequest(path: "api/v1/courses")
        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CanvasCourseDTO].self, from: data)
    }
    
    public func getAssignments(courseId: Int) async throws -> [CanvasAssignmentDTO] {
        let request = try makeRequest(path: "api/v1/courses/\(courseId)/assignments")
        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([CanvasAssignmentDTO].self, from: data)
    }
}
