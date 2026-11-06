import Foundation

public enum Severity: Int, Sendable, Comparable, Codable {
    case normal
    case warning
    case critical

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Spec §1.1: limits warn at 75 % and are critical at 95 %; context warns at 75 % and is critical at 90 %.
public struct Thresholds: Sendable, Equatable {
    public var warning: Double
    public var critical: Double

    public init(warning: Double, critical: Double) {
        self.warning = warning
        self.critical = critical
    }

    public static let limits = Thresholds(warning: 75, critical: 95)
    public static let context = Thresholds(warning: 75, critical: 90)

    public func severity(for percent: Double) -> Severity {
        if percent >= critical { return .critical }
        if percent >= warning { return .warning }
        return .normal
    }
}
