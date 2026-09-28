import Foundation
import TallyDomain

/// `GET /api/v1/courses/:id/grading_periods` (one page): `{"grading_periods": [...], "meta": ...}`.
struct GradingPeriodIndexDTO: Decodable {
    struct GradingPeriodDTO: Decodable {
        let id: String
        let title: String?
        let startDate: Date?, endDate: Date?, closeDate: Date?
        let weight: Double?
        let isClosed: Bool?
    }
    let gradingPeriods: [GradingPeriodDTO]?
}

public enum GradingPeriodMapper {
    /// A period without start or end date cannot hold assignments, so it is dropped and counted.
    public static func map(_ data: Data) throws -> Mapped<GradingPeriod> {
        let decoder = CanvasJSON.decoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let dtos = try decoder.decode(GradingPeriodIndexDTO.self, from: data).gradingPeriods ?? []
        let periods = dtos.compactMap { p -> GradingPeriod? in
            guard let start = p.startDate, let end = p.endDate else { return nil }
            return GradingPeriod(id: CanvasID(p.id), title: p.title ?? "", startDate: start, endDate: end,
                                 closeDate: p.closeDate, weight: p.weight, isClosed: p.isClosed ?? false)
        }
        return Mapped(items: periods, dropped: dtos.count - periods.count)
    }
}
