import Foundation
import TallyDomain

/// The student's own course order (UX-WP-14: "Edit mode reorders and persists locally"). Pure, so
/// `HomeModel` can apply it to each new projection in O(n) and a move is the same operation the
/// list shows.
public nonisolated enum CourseOrder {
    /// `cards` in `order`'s sequence. Courses the order does not name (new this term) keep their
    /// Canvas order after the ordered ones; names of courses that are gone are ignored.
    public static func arrange(_ cards: [CourseCard], by order: [CanvasID<Course>]) -> [CourseCard] {
        guard !order.isEmpty else { return cards }
        var position: [CanvasID<Course>: Int] = [:]
        for (index, id) in order.enumerated() where position[id] == nil {
            position[id] = index
        }
        let ordered = cards.enumerated().map { offset, card in
            (key: position[card.id] ?? order.count + offset, card: card)
        }
        // Keys are unique (distinct order positions, then distinct offsets past the end), so the
        // result is deterministic.
        return ordered.sorted { $0.key < $1.key }.map(\.card)
    }

    /// `ids` after moving the elements at `source` to `destination`, with the semantics of
    /// SwiftUI's `onMove` (`destination` is an index in the list before the move).
    public static func moving(_ ids: [CanvasID<Course>], fromOffsets source: IndexSet, toOffset destination: Int)
        -> [CanvasID<Course>] {
        let moved = source.filter { $0 < ids.count }.map { ids[$0] }
        guard !moved.isEmpty else { return ids }
        var remaining: [CanvasID<Course>] = []
        var insertAt = 0
        for (index, id) in ids.enumerated() where !source.contains(index) {
            if index < destination { insertAt += 1 }
            remaining.append(id)
        }
        remaining.insert(contentsOf: moved, at: min(insertAt, remaining.count))
        return remaining
    }
}
