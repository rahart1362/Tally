import Foundation

public struct CanvasCourseDTO: Codable {
    public let id: Int
    public let name: String?
    public let courseCode: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case courseCode = "course_code"
    }
}

public struct CanvasAssignmentDTO: Codable {
    public let id: Int
    public let name: String
    public let dueAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case dueAt = "due_at"
    }
}
