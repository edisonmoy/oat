import Foundation
import GRDB

struct TemplateRepository {
    let database: AppDatabase

    func all() throws -> [Template] {
        try database.dbWriter.read { db in
            try Template.order(Column("name")).fetchAll(db)
        }
    }

    /// Seeds the built-in templates on first launch (PLAN.md §2.3 / Phase 4).
    func seedDefaultsIfEmpty() throws {
        try database.dbWriter.write { db in
            guard try Template.fetchCount(db) == 0 else { return }
            for template in TemplateRepository.defaults {
                var copy = template
                try copy.insert(db)
            }
        }
    }

    static let defaults: [Template] = [
        Template(
            id: nil,
            name: "1:1",
            systemPrompt: """
            You are summarizing a 1:1 meeting. Using the user's rough notes and the \
            transcript, produce clean notes with these sections: Context, Discussion, \
            Decisions, Action items (with owners), and Follow-ups.
            """,
            outputSchema: nil
        ),
        Template(
            id: nil,
            name: "Standup",
            systemPrompt: """
            Summarize this standup. Produce concise per-person updates and a single \
            consolidated list of Blockers and Action items.
            """,
            outputSchema: nil
        ),
        Template(
            id: nil,
            name: "Customer discovery",
            systemPrompt: """
            Summarize this customer discovery call. Sections: Customer & context, \
            Pains, Current workflow, Desired outcomes, Objections, and Next steps.
            """,
            outputSchema: nil
        ),
        Template(
            id: nil,
            name: "Interview",
            systemPrompt: """
            Summarize this interview. Sections: Candidate, Strengths, Concerns, \
            Notable answers, and a Recommendation.
            """,
            outputSchema: nil
        )
    ]
}
