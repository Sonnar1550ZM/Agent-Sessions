import Foundation

public enum AgentSessionTitleSanitizer {
    public static func normalized(_ value: String, limit: Int = 160) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let title = removingCJKSeparatorSpaces(from: collapsed)
        guard title.count > limit else {
            return title
        }
        return String(title.prefix(limit))
    }

    public static func optional(_ value: String?, limit: Int = 160) -> String? {
        guard let value else {
            return nil
        }
        let title = normalized(value, limit: limit)
        return title.isEmpty ? nil : title
    }

    private static func removingCJKSeparatorSpaces(from value: String) -> String {
        guard value.contains(" ") else {
            return value
        }

        let characters = Array(value)
        guard characters.count >= 3 else {
            return value
        }

        var result = ""
        for index in characters.indices {
            let character = characters[index]
            if character == " ",
               index > characters.startIndex,
               index < characters.index(before: characters.endIndex),
               isCJKTitleCharacter(characters[characters.index(before: index)]),
               isCJKTitleCharacter(characters[characters.index(after: index)]) {
                continue
            }
            result.append(character)
        }
        return result
    }

    private static func isCJKTitleCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
    }
}

public enum AgentKind: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode

    public var displayName: String {
        switch self {
        case .codex:
            "Codex"
        case .claudeCode:
            "Claude Code"
        }
    }

    public init(label: String) {
        let normalized = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        if normalized.contains("claude") {
            self = .claudeCode
        } else {
            self = .codex
        }
    }
}

public enum AgentCompactionStatus {
    public static let compactingTitle = "Compacting context"
    public static let compactedTitle = "Context compacted"

    public static func displayTitle(for event: String) -> String? {
        switch event.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "PreCompact":
            return compactingTitle
        case "PostCompact", "context_compacted", "compacted":
            return compactedTitle
        default:
            return nil
        }
    }

    public static func hasMatchingDisplayTitle(event: String, title: String) -> Bool {
        guard let displayTitle = displayTitle(for: event) else {
            return false
        }
        return AgentSessionTitleSanitizer.normalized(title) == displayTitle
    }
}

public enum AgentSessionVisibility {
    public static func isCodexMemoryWorkspace(agent: AgentKind, cwd: String) -> Bool {
        guard agent == .codex else {
            return false
        }

        let sessionPath = normalizedPath(cwd)
        guard !sessionPath.isEmpty else {
            return false
        }

        let memoriesPath = normalizedPath("~/.codex/memories")
        return sessionPath == memoriesPath || sessionPath.hasPrefix(memoriesPath + "/")
    }

    public static func isCodexInternalSuggestion(
        agent: AgentKind,
        title: String,
        latestResponseText: String?
    ) -> Bool {
        guard agent == .codex else {
            return false
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCodexInternalSuggestionTitle(trimmedTitle) {
            return true
        }

        guard trimmedTitle.isEmpty || isCodexPlaceholderTitle(trimmedTitle) else {
            return false
        }

        return isCodexInternalSuggestionText(latestResponseText)
    }

    public static func isCodexUnresolvedToolEvent(
        agent: AgentKind,
        title: String,
        event: String,
        latestResponseText: String?
    ) -> Bool {
        guard agent == .codex else {
            return false
        }

        let normalizedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedEvent == "PreToolUse" || normalizedEvent == "PostToolUse" else {
            return false
        }

        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return latestResponseText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }

    private static func isCodexInternalSuggestionTitle(_ value: String) -> Bool {
        let normalized = normalizedSuggestionText(value)
        guard !normalized.isEmpty else {
            return false
        }

        if isCodexProjectSuggestionText(normalized) {
            return true
        }

        if isCodexAmbientSuggestionReviewText(normalized) {
            return true
        }

        return isCodexGmailSuggestionText(normalized)
            || isCodexGoogleCalendarSuggestionText(normalized)
            || isCodexRepositorySuggestionText(normalized)
    }

    private static func isCodexInternalSuggestionText(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        let normalized = normalizedSuggestionText(value)

        return isCodexProjectSuggestionText(normalized)
            || isCodexAmbientSuggestionReviewText(normalized)
            || isCodexGmailSuggestionText(normalized)
            || isCodexGoogleCalendarSuggestionText(normalized)
            || isCodexRepositorySuggestionText(normalized)
    }

    private static func isCodexPlaceholderTitle(_ value: String) -> Bool {
        normalizedSuggestionText(value) == "thinking..."
    }

    private static func isCodexProjectSuggestionText(_ normalized: String) -> Bool {
        (normalized.hasPrefix("# overview generate 0 to 3 hyperpersonalized suggestions")
            || normalized.hasPrefix("overview generate 0 to 3 hyperpersonalized suggestions")
            || normalized.hasPrefix("generate 0 to 3 hyperpersonalized suggestions"))
            && normalized.contains("for what this user can do with codex in this local project")
    }

    private static func isCodexAmbientSuggestionReviewText(_ normalized: String) -> Bool {
        normalized.hasPrefix("you are an expert at upholding safety and compliance standards for codex ambient suggestions")
            && normalized.contains("i will present")
    }

    private static func isCodexGmailSuggestionText(_ normalized: String) -> Bool {
        if normalized.hasPrefix("gmail\u{306e}\u{76f4}\u{8fd1}5\u{65e5}\u{306e}\u{53d7}\u{4fe1}\u{30e1}\u{30fc}\u{30eb}") {
            return normalized.contains("\u{3053}\u{306e}\u{30e6}\u{30fc}\u{30b6}\u{30fc}\u{672c}\u{4eba}\u{304c}\u{4eca}\u{5bfe}\u{5fdc}\u{3059}\u{3079}\u{304d}\u{5f37}\u{3044}\u{30b7}\u{30b0}\u{30ca}\u{30eb}")
                && normalized.contains("0-5")
                && normalized.contains("\u{62bd}\u{51fa}")
        }

        return normalized.hasPrefix("gmail \u{306b}\u{6765}\u{3066}\u{3044}\u{305f} ")
            && normalized.contains("\u{524d}\u{63d0}\u{306b}")
    }

    private static func isCodexGoogleCalendarSuggestionText(_ normalized: String) -> Bool {
        let hasCalendarPrefix = normalized.hasPrefix("google calendar ")
            || normalized.hasPrefix("gcal ")
            || normalized.hasPrefix("\u{30ab}\u{30ec}\u{30f3}\u{30c0}\u{30fc}")
        guard hasCalendarPrefix else {
            return false
        }

        return normalized.contains("\u{4e88}\u{5b9a}")
            || normalized.contains("\u{4f1a}\u{8b70}")
            || normalized.contains("\u{30a4}\u{30d9}\u{30f3}\u{30c8}")
            || normalized.contains("\u{8981}\u{7d04}")
            || normalized.contains("\u{78ba}\u{8a8d}")
    }

    private static func isCodexRepositorySuggestionText(_ normalized: String) -> Bool {
        let hasRepositoryPrefix = normalized.hasPrefix("\u{3053}\u{306e}\u{30ea}\u{30dd}\u{30b8}\u{30c8}\u{30ea}\u{3067}\u{3001}")
            || normalized.hasPrefix("\u{3053}\u{306e} repo ")
            || normalized.hasPrefix("\u{3053}\u{306e} project ")
        guard hasRepositoryPrefix else {
            return false
        }

        return normalized.contains("codex")
            || normalized.contains("agent sessions")
            || normalized.contains("\u{672a}\u{30b3}\u{30df}\u{30c3}\u{30c8}")
            || normalized.contains("\u{56de}\u{5e30}\u{30c6}\u{30b9}\u{30c8}")
            || normalized.contains("\u{5b9f}\u{88c5}")
            || normalized.contains("\u{8abf}\u{67fb}")
            || normalized.contains("\u{78ba}\u{8a8d}")
    }

    private static func normalizedSuggestionText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{ff10}", with: "0")
            .replacingOccurrences(of: "\u{ff11}", with: "1")
            .replacingOccurrences(of: "\u{ff12}", with: "2")
            .replacingOccurrences(of: "\u{ff13}", with: "3")
            .replacingOccurrences(of: "\u{ff14}", with: "4")
            .replacingOccurrences(of: "\u{ff15}", with: "5")
            .replacingOccurrences(of: "\u{ff16}", with: "6")
            .replacingOccurrences(of: "\u{ff17}", with: "7")
            .replacingOccurrences(of: "\u{ff18}", with: "8")
            .replacingOccurrences(of: "\u{ff19}", with: "9")
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let expandedPath: String
        if trimmed == "~" {
            expandedPath = homePath
        } else if trimmed.hasPrefix("~/") {
            expandedPath = homePath + String(trimmed.dropFirst())
        } else {
            expandedPath = trimmed
        }

        return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
    }
}

private enum AgentSubagentDetector {
    static func isSubagent(parentSessionId: String?, sessionId: String, transcriptPath: String?) -> Bool {
        if parentSessionId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return true
        }

        return pathContainsSubagentsComponent(sessionId)
            || pathContainsSubagentsComponent(transcriptPath)
    }

    private static func pathContainsSubagentsComponent(_ value: String?) -> Bool {
        guard let value else {
            return false
        }

        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")

        return normalized.hasPrefix("subagents/")
            || normalized.contains("/subagents/")
    }
}

public enum AgentTextSanitizer {
    public static func userPromptText(_ value: String?, limit: Int = 500) -> String? {
        AgentSessionTitleSanitizer.optional(value, limit: limit)
    }

    public static func latestResponseText(
        _ value: String?,
        limit: Int = 1_000,
        compactsBlankLines: Bool = false
    ) -> String? {
        guard let value else {
            return nil
        }

        let normalizedText = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var text = displayTextByCollapsingMarkdownLinks(normalizedText)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if compactsBlankLines {
            text = textByRemovingBlankLines(text)
        }

        guard !text.isEmpty else {
            return nil
        }

        guard text.count > limit else {
            return text
        }

        return String(text.prefix(limit))
    }

    public static func userPromptTextMatches(_ value: String?, expected: String?) -> Bool {
        guard let expected = userPromptText(expected),
              !expected.isEmpty else {
            return true
        }
        guard let value = userPromptText(value),
              !value.isEmpty else {
            return false
        }

        let normalizedValue = AgentSessionTitleSanitizer.normalized(value)
        let normalizedExpected = AgentSessionTitleSanitizer.normalized(expected)
        return normalizedValue == normalizedExpected
            || normalizedValue.hasPrefix(normalizedExpected)
            || normalizedExpected.hasPrefix(normalizedValue)
    }

    private static func textByRemovingBlankLines(_ text: String) -> String {
        text
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    private static func displayTextByCollapsingMarkdownLinks(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = markdownLinkPattern.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return text
        }

        var result = ""
        var currentIndex = text.startIndex
        for match in matches {
            guard let fullRange = Range(match.range, in: text),
                  let labelRange = Range(match.range(at: 1), in: text),
                  let targetRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            result += text[currentIndex..<fullRange.lowerBound]
            result += markdownLinkDisplayText(
                label: String(text[labelRange]),
                target: String(text[targetRange])
            ) ?? String(text[fullRange])
            currentIndex = fullRange.upperBound
        }
        result += text[currentIndex...]

        return result
    }

    private static func markdownLinkDisplayText(label: String, target: String) -> String? {
        let displayLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTarget = markdownLinkTarget(target)
        guard isLocalFileLinkTarget(normalizedTarget),
              let lineNumber = markdownLinkLineNumber(normalizedTarget) else {
            return nil
        }

        return "\(displayLabel) (line \(lineNumber))"
    }

    private static func markdownLinkTarget(_ target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), trimmed.count >= 2 else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
    }

    private static func isLocalFileLinkTarget(_ target: String) -> Bool {
        target.hasPrefix("/")
            || target.hasPrefix("~/")
            || target.hasPrefix("file://")
    }

    private static func markdownLinkLineNumber(_ target: String) -> String? {
        let range = NSRange(target.startIndex..<target.endIndex, in: target)
        guard let match = lineNumberSuffixPattern.firstMatch(in: target, range: range),
              let lineRange = Range(match.range(at: 1), in: target) else {
            return nil
        }

        return String(target[lineRange])
    }

    private static let markdownLinkPattern = try! NSRegularExpression(
        pattern: #"(?<!!)\[([^\]\n]+)\]\((<[^>\n]+>|[^)\n]+)\)"#
    )
    private static let lineNumberSuffixPattern = try! NSRegularExpression(
        pattern: #"(?::|#L)(\d+)$"#
    )
}

public enum AgentState: String, Codable, CaseIterable, Sendable {
    case working
    case waiting
    case idle
    case ended

    public var symbol: String {
        switch self {
        case .working:
            "●"
        case .waiting:
            "△"
        case .idle:
            "○"
        case .ended:
            "-"
        }
    }

    public var displayName: String {
        switch self {
        case .working:
            "Working"
        case .waiting:
            "Waiting"
        case .idle:
            "Idle"
        case .ended:
            "Ended"
        }
    }

    public var isActive: Bool {
        self == .working || self == .waiting
    }

    public init(label: String?) {
        let normalized = (label ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalized {
        case "working", "work", "busy", "auto", "posttooluse", "pretooluse", "userpromptsubmit":
            self = .working
        case "waiting", "wait", "notification", "permission":
            self = .waiting
        case "ended", "end", "sessionend":
            self = .ended
        case "idle", "stop", "sessionstart":
            self = .idle
        default:
            self = .idle
        }
    }
}

public struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var event: String
    public var terminal: String
    public var pid: Int?
    public var updatedAt: Date
    public var parentSessionId: String?
    public var subagentNickname: String?
    public var subagentRole: String?
    public var subagentDepth: Int?
    public var transcriptPath: String?
    public var latestUserPrompt: String?
    public var latestResponseText: String?
    public var latestResponsePhase: String?
    public var latestResponseUpdatedAt: Date?
    public var stateChangedAt: Date?

    public var id: String {
        "\(agent.rawValue):\(sessionId)"
    }

    public var isSubagent: Bool {
        AgentSubagentDetector.isSubagent(
            parentSessionId: parentSessionId,
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )
    }

    public var hasLatestResponseText: Bool {
        AgentTextSanitizer.latestResponseText(latestResponseText)?.isEmpty == false
    }

    public var isAwaitingLatestResponseText: Bool {
        state == .working && !hasLatestResponseText
    }

    public init(
        agent: AgentKind,
        sessionId: String,
        state: AgentState,
        title: String = "",
        cwd: String = "",
        event: String = "",
        terminal: String = "",
        pid: Int? = nil,
        updatedAt: Date = Date(),
        parentSessionId: String? = nil,
        subagentNickname: String? = nil,
        subagentRole: String? = nil,
        subagentDepth: Int? = nil,
        transcriptPath: String? = nil,
        latestUserPrompt: String? = nil,
        latestResponseText: String? = nil,
        latestResponsePhase: String? = nil,
        latestResponseUpdatedAt: Date? = nil,
        stateChangedAt: Date? = nil
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.state = state
        self.title = AgentSessionTitleSanitizer.normalized(title)
        self.cwd = cwd
        self.event = event
        self.terminal = terminal
        self.pid = pid
        self.updatedAt = updatedAt
        self.parentSessionId = parentSessionId
        self.subagentNickname = subagentNickname
        self.subagentRole = subagentRole
        self.subagentDepth = subagentDepth
        self.transcriptPath = transcriptPath
        self.latestUserPrompt = AgentTextSanitizer.userPromptText(latestUserPrompt)
        self.latestResponseText = latestResponseText
        self.latestResponsePhase = latestResponsePhase
        self.latestResponseUpdatedAt = latestResponseUpdatedAt
        self.stateChangedAt = stateChangedAt ?? updatedAt
    }

    public var displayTitle: String {
        let explicitTitle = AgentSessionTitleSanitizer.normalized(title)
        if !explicitTitle.isEmpty {
            return explicitTitle
        }

        if isSubagent,
           let subagentNickname = subagentNickname?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subagentNickname.isEmpty {
            return subagentNickname
        }

        if agent == .codex {
            return "Codex session"
        }

        if !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: cwd).lastPathComponent
        }

        return sessionId
    }

    public var subagentDisplayLabel: String {
        let explicitTitle = AgentSessionTitleSanitizer.normalized(title)
        let role = Self.formattedSubagentRole(subagentRole)
        let name = subagentNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []

        if !explicitTitle.isEmpty {
            if !role.isEmpty,
               Self.normalizedSubagentLabel(explicitTitle) == Self.normalizedSubagentLabel(role) {
                parts.append(role)
            } else {
                parts.append(explicitTitle)
            }
        } else {
            let fallbackTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackTitle.isEmpty,
               Self.normalizedSubagentLabel(fallbackTitle) != Self.normalizedSubagentLabel(name),
               Self.normalizedSubagentLabel(fallbackTitle) != Self.normalizedSubagentLabel(role) {
                parts.append(fallbackTitle)
            }
        }

        if !role.isEmpty,
           !parts.contains(where: { Self.normalizedSubagentLabel($0) == Self.normalizedSubagentLabel(role) }) {
            parts.append(role)
        }

        if !name.isEmpty,
           !parts.contains(where: { Self.normalizedSubagentLabel($0) == Self.normalizedSubagentLabel(name) }) {
            parts.append(name)
        }

        return parts.isEmpty ? sessionId : parts.joined(separator: " · ")
    }

    public var subagentSessionTitle: String {
        let explicitTitle = AgentSessionTitleSanitizer.normalized(title)
        if !explicitTitle.isEmpty {
            return explicitTitle
        }

        let fallbackTitle = displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallbackTitle.isEmpty ? sessionId : fallbackTitle
    }

    public var subagentNameAndRoleLabel: String {
        let name = subagentNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let role = Self.formattedSubagentRole(subagentRole)
        var parts: [String] = []

        if !name.isEmpty {
            parts.append(name)
        }

        if !role.isEmpty,
           !parts.contains(where: { Self.normalizedSubagentLabel($0) == Self.normalizedSubagentLabel(role) }) {
            parts.append(role)
        }

        return parts.isEmpty ? sessionId : parts.joined(separator: " · ")
    }

    private static func formattedSubagentRole(_ role: String?) -> String {
        let trimmedRole = role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedRole.isEmpty else {
            return ""
        }

        let normalized = trimmedRole
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let words = normalized.split(separator: " ")
        guard !words.isEmpty else {
            return trimmedRole
        }

        return words
            .map { word -> String in
                let text = String(word)
                guard text == text.lowercased() else {
                    return text
                }
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func normalizedSubagentLabel(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
    }
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public var agent: AgentKind
    public var sessionId: String
    public var state: AgentState
    public var title: String
    public var cwd: String
    public var event: String
    public var terminal: String
    public var pid: Int?
    public var updatedAt: Date?
    public var parentSessionId: String?
    public var subagentNickname: String?
    public var subagentRole: String?
    public var subagentDepth: Int?
    public var transcriptPath: String?
    public var latestUserPrompt: String?
    public var latestResponseText: String?
    public var latestResponsePhase: String?

    public var isSubagent: Bool {
        AgentSubagentDetector.isSubagent(
            parentSessionId: parentSessionId,
            sessionId: sessionId,
            transcriptPath: transcriptPath
        )
    }

    private enum CodingKeys: String, CodingKey {
        case agent
        case sessionId
        case sessionID
        case session_id
        case state
        case title
        case cwd
        case event
        case terminal
        case pid
        case updatedAt
        case updated_at
        case parentSessionId
        case parent_session_id
        case subagentNickname
        case subagent_nickname
        case subagentRole
        case subagent_role
        case subagentDepth
        case subagent_depth
        case transcriptPath
        case transcript_path
        case latestUserPrompt
        case latest_user_prompt
        case userPrompt
        case user_prompt
        case latestResponseText
        case latest_response_text
        case latestResponsePhase
        case latest_response_phase
    }

    public init(
        agent: AgentKind,
        sessionId: String,
        state: AgentState,
        title: String = "",
        cwd: String = "",
        event: String = "",
        terminal: String = "",
        pid: Int? = nil,
        updatedAt: Date? = nil,
        parentSessionId: String? = nil,
        subagentNickname: String? = nil,
        subagentRole: String? = nil,
        subagentDepth: Int? = nil,
        transcriptPath: String? = nil,
        latestUserPrompt: String? = nil,
        latestResponseText: String? = nil,
        latestResponsePhase: String? = nil
    ) {
        self.agent = agent
        self.sessionId = sessionId
        self.state = state
        self.title = AgentSessionTitleSanitizer.normalized(title)
        self.cwd = cwd
        self.event = event
        self.terminal = terminal
        self.pid = pid
        self.updatedAt = updatedAt
        self.parentSessionId = parentSessionId
        self.subagentNickname = subagentNickname
        self.subagentRole = subagentRole
        self.subagentDepth = subagentDepth
        self.transcriptPath = transcriptPath
        self.latestUserPrompt = AgentTextSanitizer.userPromptText(latestUserPrompt)
        self.latestResponseText = latestResponseText
        self.latestResponsePhase = latestResponsePhase
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let agentLabel = try container.decodeIfPresent(String.self, forKey: .agent) ?? "Codex"
        let rawTranscriptPath = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .transcriptPath,
            fallbackKey: .transcript_path,
            limit: 1024
        )
        let rawSessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
            ?? container.decodeIfPresent(String.self, forKey: .sessionID)
            ?? container.decodeIfPresent(String.self, forKey: .session_id)
            ?? Self.sessionId(fromTranscriptPath: rawTranscriptPath)
        let rawState = try container.decodeIfPresent(String.self, forKey: .state)

        agent = AgentKind(label: agentLabel)
        let normalizedSessionId = rawSessionId?.trimmed(limit: 160) ?? ""
        guard !normalizedSessionId.isEmpty, normalizedSessionId != "default" else {
            throw DecodingError.dataCorruptedError(
                forKey: .sessionId,
                in: container,
                debugDescription: "Agent event requires a unique sessionId."
            )
        }
        sessionId = normalizedSessionId
        state = AgentState(label: rawState)
        title = AgentSessionTitleSanitizer.normalized(
            try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        )
        cwd = (try container.decodeIfPresent(String.self, forKey: .cwd) ?? "").trimmed(limit: 512)
        event = (try container.decodeIfPresent(String.self, forKey: .event) ?? "").trimmed(limit: 80)
        terminal = (try container.decodeIfPresent(String.self, forKey: .terminal) ?? "").trimmed(limit: 80)
        pid = try container.decodeIfPresent(Int.self, forKey: .pid)
        parentSessionId = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .parentSessionId,
            fallbackKey: .parent_session_id,
            limit: 160
        )
        subagentNickname = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .subagentNickname,
            fallbackKey: .subagent_nickname,
            limit: 80
        )
        subagentRole = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .subagentRole,
            fallbackKey: .subagent_role,
            limit: 80
        )
        subagentDepth = try container.decodeIfPresent(Int.self, forKey: .subagentDepth)
            ?? container.decodeIfPresent(Int.self, forKey: .subagent_depth)
        transcriptPath = rawTranscriptPath
        latestUserPrompt = try Self.decodeUserPromptText(from: container, limit: 500)
        latestResponseText = try Self.decodeLatestResponseText(
            from: container,
            primaryKey: .latestResponseText,
            fallbackKey: .latest_response_text,
            limit: 1000
        )
        latestResponsePhase = try Self.decodeTrimmedOptionalString(
            from: container,
            primaryKey: .latestResponsePhase,
            fallbackKey: .latest_response_phase,
            limit: 80
        )

        if let date = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(Date.self, forKey: .updated_at) {
            updatedAt = date
        } else if let dateString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? container.decodeIfPresent(String.self, forKey: .updated_at) {
            updatedAt = AgentSessionsDates.date(from: dateString)
        } else {
            updatedAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agent.rawValue, forKey: .agent)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(state.rawValue, forKey: .state)
        try container.encode(title, forKey: .title)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(event, forKey: .event)
        try container.encode(terminal, forKey: .terminal)
        try container.encodeIfPresent(pid, forKey: .pid)
        if let updatedAt {
            try container.encode(AgentSessionsDates.string(from: updatedAt), forKey: .updatedAt)
        }
        try container.encodeIfPresent(parentSessionId, forKey: .parentSessionId)
        try container.encodeIfPresent(subagentNickname, forKey: .subagentNickname)
        try container.encodeIfPresent(subagentRole, forKey: .subagentRole)
        try container.encodeIfPresent(subagentDepth, forKey: .subagentDepth)
        try container.encodeIfPresent(transcriptPath, forKey: .transcriptPath)
        try container.encodeIfPresent(latestUserPrompt, forKey: .latestUserPrompt)
        try container.encodeIfPresent(latestResponseText, forKey: .latestResponseText)
        try container.encodeIfPresent(latestResponsePhase, forKey: .latestResponsePhase)
    }

    private static func decodeTrimmedOptionalString(
        from container: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        fallbackKey: CodingKeys,
        limit: Int
    ) throws -> String? {
        let value = try container.decodeIfPresent(String.self, forKey: primaryKey)
            ?? container.decodeIfPresent(String.self, forKey: fallbackKey)
            ?? ""
        let trimmed = value.trimmed(limit: limit)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodeLatestResponseText(
        from container: KeyedDecodingContainer<CodingKeys>,
        primaryKey: CodingKeys,
        fallbackKey: CodingKeys,
        limit: Int
    ) throws -> String? {
        let value = try container.decodeIfPresent(String.self, forKey: primaryKey)
            ?? container.decodeIfPresent(String.self, forKey: fallbackKey)
        return AgentTextSanitizer.latestResponseText(value, limit: limit)
    }

    private static func decodeUserPromptText(
        from container: KeyedDecodingContainer<CodingKeys>,
        limit: Int
    ) throws -> String? {
        let value = try container.decodeIfPresent(String.self, forKey: .latestUserPrompt)
            ?? container.decodeIfPresent(String.self, forKey: .latest_user_prompt)
            ?? container.decodeIfPresent(String.self, forKey: .userPrompt)
            ?? container.decodeIfPresent(String.self, forKey: .user_prompt)
        return AgentTextSanitizer.userPromptText(value, limit: limit)
    }

    private static func sessionId(fromTranscriptPath transcriptPath: String?) -> String? {
        guard let transcriptPath,
              !transcriptPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let fileName = URL(fileURLWithPath: transcriptPath).lastPathComponent
        guard fileName.hasSuffix(".jsonl") else {
            return nil
        }

        let sessionId = String(fileName.dropLast(".jsonl".count)).trimmed(limit: 160)
        return sessionId.isEmpty ? nil : sessionId
    }
}

public enum AgentSessionsDates {
    private static let sharedFormatter = LockedAgentSessionsDateFormatter()

    public static func string(from date: Date) -> String {
        sharedFormatter.string(from: date)
    }

    public static func date(from value: String) -> Date? {
        sharedFormatter.date(from: value)
    }
}

private final class LockedAgentSessionsDateFormatter: @unchecked Sendable {
    private let lock = NSLock()
    private let formatter: ISO8601DateFormatter

    init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func string(from date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(from: date)
    }

    func date(from value: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return formatter.date(from: value)
    }
}

private extension String {
    func trimmed(limit: Int) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= limit {
            return trimmed
        }
        return String(trimmed.prefix(limit))
    }

}
