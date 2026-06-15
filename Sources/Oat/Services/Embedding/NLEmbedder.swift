import NaturalLanguage

/// On-device sentence embeddings via Apple's Natural Language framework.
/// Returns 512-dimensional Float vectors. Available on macOS 12+ without any
/// model download — the sentence embedding model ships with the OS.
///
/// If the embedding model is unavailable (e.g. unsupported locale),
/// `init()` returns nil and the caller falls back to `UnimplementedEmbedder`.
struct NLEmbedder: Embedder {
    private let embedding: NLEmbedding

    init?() {
        guard let e = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        embedding = e
    }

    func embed(_ text: String) -> [Float] {
        guard let vector = embedding.vector(for: text) else { return [] }
        return vector.map { Float($0) }
    }
}
