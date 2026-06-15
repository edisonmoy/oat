import Accelerate

enum VectorMath {
    /// Cosine similarity in [-1, 1]. Returns 0 for zero-length or mismatched vectors.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let n = vDSP_Length(a.count)
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, n)
        vDSP_svesq(a, 1, &magA, n)
        vDSP_svesq(b, 1, &magB, n)
        let denom = sqrt(magA) * sqrt(magB)
        return denom > 0 ? dot / denom : 0
    }

    /// Returns up to `k` candidates sorted by descending score.
    static func topK(_ candidates: [(id: Int64, score: Float)], k: Int) -> [(id: Int64, score: Float)] {
        Array(candidates.sorted { $0.score > $1.score }.prefix(k))
    }
}
