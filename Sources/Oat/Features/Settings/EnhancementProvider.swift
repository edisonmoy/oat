import Foundation

/// Where note enhancement runs. Mirrors the local/cloud split in PLAN.md §3.2.
enum EnhancementProvider: String, CaseIterable, Identifiable {
    case cloud
    case local

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cloud: return "Cloud (Claude) — best quality"
        case .local: return "On-device (Apple) — fully private"
        }
    }
}
