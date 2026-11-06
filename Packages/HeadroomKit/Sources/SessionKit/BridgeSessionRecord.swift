import Foundation

/// What the bridge knows about one session (spec §2.4, §2.5), merged from its
/// `<id>.hook.json` and `<id>.statusline.json` files.
public struct BridgeSessionRecord: Sendable, Equatable {
    public var sessionId: String
    public var pid: Int32?
    public var cwd: String?
    public var transcriptPath: String?
    public var lastEvent: String?
    public var lastEventAt: Date?
    public var notificationType: String?
    public var statusLineAt: Date?
    public var contextWindowSize: Int?
    public var contextUsedPercent: Double?
    public var modelId: String?

    public init(
        sessionId: String,
        pid: Int32? = nil,
        cwd: String? = nil,
        transcriptPath: String? = nil,
        lastEvent: String? = nil,
        lastEventAt: Date? = nil,
        notificationType: String? = nil,
        statusLineAt: Date? = nil,
        contextWindowSize: Int? = nil,
        contextUsedPercent: Double? = nil,
        modelId: String? = nil
    ) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.lastEvent = lastEvent
        self.lastEventAt = lastEventAt
        self.notificationType = notificationType
        self.statusLineAt = statusLineAt
        self.contextWindowSize = contextWindowSize
        self.contextUsedPercent = contextUsedPercent
        self.modelId = modelId
    }

    /// The newest of `lastEventAt` and `statusLineAt`.
    public var lastSeenAt: Date? {
        [lastEventAt, statusLineAt].compactMap { $0 }.max()
    }
}
