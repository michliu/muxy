import Foundation

public struct SelectProjectParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct ExtensionRequestParams: Codable, Sendable {
    public let `extension`: String
    public let action: String
    public let payload: MuxyJSON

    public init(extension: String, action: String, payload: MuxyJSON = .null) {
        self.extension = `extension`
        self.action = action
        self.payload = payload
    }
}

public struct ExtensionResultDTO: Codable, Sendable {
    public let payload: MuxyJSON

    public init(payload: MuxyJSON) {
        self.payload = payload
    }
}

public struct ListWorktreesParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct SelectWorktreeParams: Codable, Sendable {
    public let projectID: UUID
    public let worktreeID: UUID
    public init(projectID: UUID, worktreeID: UUID) {
        self.projectID = projectID
        self.worktreeID = worktreeID
    }
}

public struct GetWorkspaceParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct CreateTabParams: Codable, Sendable {
    public let projectID: UUID
    public let areaID: UUID?
    public let kind: TabKindDTO
    public init(projectID: UUID, areaID: UUID? = nil, kind: TabKindDTO = .terminal) {
        self.projectID = projectID
        self.areaID = areaID
        self.kind = kind
    }
}

public struct CloseTabParams: Codable, Sendable {
    public let projectID: UUID
    public let areaID: UUID
    public let tabID: UUID
    public init(projectID: UUID, areaID: UUID, tabID: UUID) {
        self.projectID = projectID
        self.areaID = areaID
        self.tabID = tabID
    }
}

public struct SelectTabParams: Codable, Sendable {
    public let projectID: UUID
    public let areaID: UUID
    public let tabID: UUID
    public init(projectID: UUID, areaID: UUID, tabID: UUID) {
        self.projectID = projectID
        self.areaID = areaID
        self.tabID = tabID
    }
}

public struct SplitAreaParams: Codable, Sendable {
    public let projectID: UUID
    public let areaID: UUID
    public let direction: SplitDirectionDTO
    public let position: SplitPositionDTO
    public init(projectID: UUID, areaID: UUID, direction: SplitDirectionDTO, position: SplitPositionDTO) {
        self.projectID = projectID
        self.areaID = areaID
        self.direction = direction
        self.position = position
    }
}

public enum SplitPositionDTO: String, Codable, Sendable {
    case first
    case second
}

public struct CloseAreaParams: Codable, Sendable {
    public let projectID: UUID
    public let areaID: UUID
    public init(projectID: UUID, areaID: UUID) {
        self.projectID = projectID
        self.areaID = areaID
    }
}

public struct FocusAreaParams: Codable, Sendable {
    public let projectID: UUID
    public let areaID: UUID
    public init(projectID: UUID, areaID: UUID) {
        self.projectID = projectID
        self.areaID = areaID
    }
}

public struct AttachPaneParams: Codable, Sendable {
    public let paneID: UUID
    public init(paneID: UUID) {
        self.paneID = paneID
    }
}

public struct DetachPaneParams: Codable, Sendable {
    public let paneID: UUID
    public init(paneID: UUID) {
        self.paneID = paneID
    }
}

public struct ResyncPaneParams: Codable, Sendable {
    public let paneID: UUID
    public let haveOffset: UInt64
    public init(paneID: UUID, haveOffset: UInt64) {
        self.paneID = paneID
        self.haveOffset = haveOffset
    }
}

public struct RegisterDeviceParams: Codable, Sendable {
    public let deviceName: String
    public init(deviceName: String) {
        self.deviceName = deviceName
    }
}

public struct PairDeviceParams: Codable, Sendable {
    public let deviceID: UUID
    public let deviceName: String
    public let token: String
    public init(deviceID: UUID, deviceName: String, token: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.token = token
    }
}

public struct AuthenticateDeviceParams: Codable, Sendable {
    public let deviceID: UUID
    public let deviceName: String
    public let token: String
    public init(deviceID: UUID, deviceName: String, token: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.token = token
    }
}

public struct PairingResultDTO: Codable, Sendable {
    public let clientID: UUID
    public let deviceName: String
    public let themeFg: UInt32?
    public let themeBg: UInt32?
    public let themePalette: [UInt32]?
    public init(clientID: UUID, deviceName: String, themeFg: UInt32? = nil, themeBg: UInt32? = nil, themePalette: [UInt32]? = nil) {
        self.clientID = clientID
        self.deviceName = deviceName
        self.themeFg = themeFg
        self.themeBg = themeBg
        self.themePalette = themePalette
    }
}

public struct DeviceInfoDTO: Codable, Sendable {
    public let clientID: UUID
    public let deviceName: String
    public let themeFg: UInt32?
    public let themeBg: UInt32?
    public let themePalette: [UInt32]?
    public init(clientID: UUID, deviceName: String, themeFg: UInt32? = nil, themeBg: UInt32? = nil, themePalette: [UInt32]? = nil) {
        self.clientID = clientID
        self.deviceName = deviceName
        self.themeFg = themeFg
        self.themeBg = themeBg
        self.themePalette = themePalette
    }
}

public struct TerminalAttachDTO: Codable, Sendable {
    public let paneID: UUID
    public let cols: UInt32
    public let rows: UInt32
    public let baseOffset: UInt64
    public let snapshot: Data
    public init(paneID: UUID, cols: UInt32, rows: UInt32, baseOffset: UInt64, snapshot: Data) {
        self.paneID = paneID
        self.cols = cols
        self.rows = rows
        self.baseOffset = baseOffset
        self.snapshot = snapshot
    }
}

public struct TerminalDetachedEventDTO: Codable, Sendable {
    public let paneID: UUID
    public init(paneID: UUID) {
        self.paneID = paneID
    }
}

public struct DeviceThemeEventDTO: Codable, Sendable {
    public let fg: UInt32
    public let bg: UInt32
    public let palette: [UInt32]?
    public init(fg: UInt32, bg: UInt32, palette: [UInt32]? = nil) {
        self.fg = fg
        self.bg = bg
        self.palette = palette
    }
}

public struct GetVCSStatusParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct VCSRefreshParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct VCSCommitParams: Codable, Sendable {
    public let projectID: UUID
    public let message: String
    public let stageAll: Bool
    public init(projectID: UUID, message: String, stageAll: Bool = false) {
        self.projectID = projectID
        self.message = message
        self.stageAll = stageAll
    }
}

public struct VCSPushParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct VCSPullParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct VCSStageFilesParams: Codable, Sendable {
    public let projectID: UUID
    public let paths: [String]
    public init(projectID: UUID, paths: [String]) {
        self.projectID = projectID
        self.paths = paths
    }
}

public struct VCSUnstageFilesParams: Codable, Sendable {
    public let projectID: UUID
    public let paths: [String]
    public init(projectID: UUID, paths: [String]) {
        self.projectID = projectID
        self.paths = paths
    }
}

public struct VCSDiscardFilesParams: Codable, Sendable {
    public let projectID: UUID
    public let paths: [String]
    public let untrackedPaths: [String]
    public init(projectID: UUID, paths: [String], untrackedPaths: [String]) {
        self.projectID = projectID
        self.paths = paths
        self.untrackedPaths = untrackedPaths
    }
}

public struct VCSListBranchesParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct VCSSwitchBranchParams: Codable, Sendable {
    public let projectID: UUID
    public let branch: String
    public init(projectID: UUID, branch: String) {
        self.projectID = projectID
        self.branch = branch
    }
}

public struct VCSCreateBranchParams: Codable, Sendable {
    public let projectID: UUID
    public let name: String
    public init(projectID: UUID, name: String) {
        self.projectID = projectID
        self.name = name
    }
}

public struct VCSCreatePRParams: Codable, Sendable {
    public let projectID: UUID
    public let title: String
    public let body: String
    public let baseBranch: String?
    public let draft: Bool
    public init(projectID: UUID, title: String, body: String, baseBranch: String?, draft: Bool) {
        self.projectID = projectID
        self.title = title
        self.body = body
        self.baseBranch = baseBranch
        self.draft = draft
    }
}

public enum VCSMergeMethodDTO: String, Codable, Sendable {
    case merge
    case squash
    case rebase
}

public struct VCSMergePullRequestParams: Codable, Sendable {
    public let projectID: UUID
    public let number: Int
    public let method: VCSMergeMethodDTO
    public let deleteBranch: Bool
    public init(projectID: UUID, number: Int, method: VCSMergeMethodDTO, deleteBranch: Bool) {
        self.projectID = projectID
        self.number = number
        self.method = method
        self.deleteBranch = deleteBranch
    }
}

public struct VCSAddWorktreeParams: Codable, Sendable {
    public let projectID: UUID
    public let name: String
    public let branch: String
    public let createBranch: Bool
    public let baseBranch: String?
    public init(
        projectID: UUID,
        name: String,
        branch: String,
        createBranch: Bool,
        baseBranch: String? = nil
    ) {
        self.projectID = projectID
        self.name = name
        self.branch = branch
        self.createBranch = createBranch
        self.baseBranch = baseBranch
    }
}

public struct VCSRemoveWorktreeParams: Codable, Sendable {
    public let projectID: UUID
    public let worktreeID: UUID
    public init(projectID: UUID, worktreeID: UUID) {
        self.projectID = projectID
        self.worktreeID = worktreeID
    }
}

public struct VCSGetDiffParams: Codable, Sendable {
    public let projectID: UUID
    public let filePath: String
    public let forceFull: Bool

    public init(projectID: UUID, filePath: String, forceFull: Bool = false) {
        self.projectID = projectID
        self.filePath = filePath
        self.forceFull = forceFull
    }
}

public struct GetProjectLogoParams: Codable, Sendable {
    public let projectID: UUID
    public init(projectID: UUID) {
        self.projectID = projectID
    }
}

public struct ProjectLogoDTO: Codable, Sendable {
    public let projectID: UUID
    public let pngData: String

    public init(projectID: UUID, pngData: String) {
        self.projectID = projectID
        self.pngData = pngData
    }
}

public struct MarkNotificationReadParams: Codable, Sendable {
    public let notificationID: UUID
    public init(notificationID: UUID) {
        self.notificationID = notificationID
    }
}

public struct SubscribeParams: Codable, Sendable {
    public let events: [MuxyEventKind]
    public init(events: [MuxyEventKind]) {
        self.events = events
    }
}

public struct UnsubscribeParams: Codable, Sendable {
    public let events: [MuxyEventKind]
    public init(events: [MuxyEventKind]) {
        self.events = events
    }
}
