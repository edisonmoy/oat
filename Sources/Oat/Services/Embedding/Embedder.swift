import Foundation

/// Produces vector embeddings for semantic search. Kept on-device (PLAN.md §3.2)
/// using the Natural Language framework's `NLEmbedding` (or a small CoreML model),
/// with vectors stored via sqlite-vec. Phase 6.
protocol Embedder {
    func embed(_ text: String) -> [Float]
}

struct UnimplementedEmbedder: Embedder {
    func embed(_ text: String) -> [Float] { [] }
}
