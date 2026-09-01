import Foundation

public struct AnalyticsBridgeDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data) throws -> AnalyticsSnapshot { try decodeSnapshot(data) }

    public func decodeSnapshot(_ data: Data) throws -> AnalyticsSnapshot {
        guard data.count <= 256 * 1024 else { throw AnalyticsDecodeSupport.fail([], "Analytics document exceeds 256 KiB.") }
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let envelope = root as? [String: Any] else { throw AnalyticsDecodeSupport.fail([], "Expected an object.") }
        try keys(envelope, ["schemaVersion", "ok", "generatedAt", "data", "errors"])
        guard string(envelope, "schemaVersion") == AnalyticsDecodeSupport.schema else { throw AnalyticsDecodeSupport.fail([], "Unsupported analytics schema.") }
        guard let ok = envelope["ok"] as? Bool else { throw AnalyticsDecodeSupport.fail([], "Invalid ok value.") }
        let generatedAt = try date(envelope["generatedAt"])
        let envelopeErrors = try errors(envelope["errors"])
        let rawData = envelope["data"]
        if !ok {
            guard rawData is NSNull, !envelopeErrors.isEmpty else { throw AnalyticsDecodeSupport.fail([], "Failed analytics envelope must have null data and errors.") }
            throw AnalyticsDecodeSupport.fail([], "Analytics bridge returned a failure.")
        }
        guard let payload = rawData as? [String: Any] else { throw AnalyticsDecodeSupport.fail([], "Successful analytics envelope requires data.") }
        try keys(payload, ["analysisRange", "repositories", "unattributed", "coverage", "errors"])
        let rangeObject = try object(payload["analysisRange"])
        try keys(rangeObject, ["start", "end"])
        let rangeStart = try date(rangeObject["start"])
        let rangeEnd = try date(rangeObject["end"])
        let range = AnalyticsDateRange(start: rangeStart, end: rangeEnd)
        let rangeIsValid = range.end == generatedAt && range.end.timeIntervalSince(range.start) == 30 * 24 * 60 * 60
        guard rangeIsValid else { throw AnalyticsDecodeSupport.fail([], "Analytics range must be exactly 30 days ending at generatedAt.") }
        let repositories = try requiredArray(payload, "repositories").map(repository)
        guard repositories.count <= 64 else { throw AnalyticsDecodeSupport.fail([], "Too many repositories.") }
        var repositoryIDs = Set<String>()
        for repository in repositories { guard repositoryIDs.insert(repository.repositoryID).inserted else { throw AnalyticsDecodeSupport.fail([], "Duplicate repository ID.") } }
        for repository in repositories {
            guard repository.commits.allSatisfy({ $0.committedAt <= generatedAt }) else { throw AnalyticsDecodeSupport.fail([], "Commit timestamp is outside the analysis capture.") }
        }
        for pair in zip(repositories, repositories.dropFirst()) {
            let left = pair.0.usage.estimatedCostUSDValue ?? 0
            let right = pair.1.usage.estimatedCostUSDValue ?? 0
            guard left >= right && (left != right || pair.0.repositoryID <= pair.1.repositoryID) else { throw AnalyticsDecodeSupport.fail([], "Repositories are not deterministically ordered.") }
        }
        let unattributed = try attribution(payload["unattributed"])
        let coverage = try analyticsCoverage(payload["coverage"])
        let payloadErrors = try errors(payload["errors"])
        return AnalyticsSnapshot(schemaVersion: AnalyticsDecodeSupport.schema, ok: true, generatedAt: generatedAt,
                                 analysisRange: range, repositories: repositories, unattributed: unattributed,
                                 coverage: coverage, errors: envelopeErrors + payloadErrors)
    }

    private func repository(_ raw: Any) throws -> AnalyticsRepositoryAnalytics {
        let value = try object(raw)
        try keys(value, ["repositoryID", "label", "state", "usage", "observedActiveTimeSeconds", "providerModels", "commits", "coverage"])
        let id = try requiredString(value, "repositoryID")
        guard id.range(of: #"^r[0-9a-f]{8}$"#, options: .regularExpression) != nil else { throw AnalyticsDecodeSupport.fail([], "Invalid repository ID.") }
        let label = try requiredString(value, "label")
        guard !label.isEmpty, label.utf8.count <= 80, label.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw AnalyticsDecodeSupport.fail([], "Invalid repository label.") }
        let state = try requiredString(value, "state")
        guard AnalyticsDecodeSupport.states.contains(state) else { throw AnalyticsDecodeSupport.fail([], "Unknown repository state.") }
        let active = try integer(value["observedActiveTimeSeconds"])
        let models = try requiredArray(value, "providerModels").map(providerModel)
        guard models.count <= 256 else { throw AnalyticsDecodeSupport.fail([], "Too many provider model rows.") }
        for pair in zip(models, models.dropFirst()) { guard (pair.0.provider, pair.0.model) <= (pair.1.provider, pair.1.model) else { throw AnalyticsDecodeSupport.fail([], "Provider models are not ordered.") } }
        let commits = try requiredArray(value, "commits").map(commit)
        guard commits.count <= 200 else { throw AnalyticsDecodeSupport.fail([], "Too many commits.") }
        var ids = Set<String>()
        for commit in commits {
            guard ids.insert(commit.commitID).inserted else { throw AnalyticsDecodeSupport.fail([], "Duplicate commit ID.") }
        }
        for pair in zip(commits, commits.dropFirst()) { guard pair.0.committedAt >= pair.1.committedAt && (pair.0.committedAt != pair.1.committedAt || pair.0.commitID <= pair.1.commitID) else { throw AnalyticsDecodeSupport.fail([], "Commits are not ordered.") } }
        return AnalyticsRepositoryAnalytics(repositoryID: id, label: label, state: state, usage: try usage(value["usage"]), observedActiveTimeSeconds: active,
                                             providerModels: models, commits: commits, coverage: try repositoryCoverage(value["coverage"]))
    }

    private func providerModel(_ raw: Any) throws -> AnalyticsProviderModelAnalytics {
        let value = try object(raw)
        try keys(value, ["provider", "model", "usage", "costPer1KTokens", "tokensPerObservedActiveHour", "millisecondsPer1KTokens", "costCoverage", "timingCoverage"])
        let provider = try requiredString(value, "provider")
        guard AnalyticsDecodeSupport.providers.contains(provider) else { throw AnalyticsDecodeSupport.fail([], "Unknown provider.") }
        let model = try requiredString(value, "model")
        guard model.range(of: #"^(Other model|[A-Za-z0-9][A-Za-z0-9._:-]{0,79})$"#, options: .regularExpression) != nil else { throw AnalyticsDecodeSupport.fail([], "Invalid model name.") }
        let costCoverage = try requiredString(value, "costCoverage")
        let timingCoverage = try requiredString(value, "timingCoverage")
        guard AnalyticsDecodeSupport.costCoverage.contains(costCoverage), AnalyticsDecodeSupport.timingCoverage.contains(timingCoverage) else { throw AnalyticsDecodeSupport.fail([], "Unknown coverage.") }
        return AnalyticsProviderModelAnalytics(provider: provider, model: model, usage: try usage(value["usage"]),
                                                costPer1KTokens: try optionalDecimal(value["costPer1KTokens"]),
                                                tokensPerObservedActiveHour: try optionalDecimal(value["tokensPerObservedActiveHour"]),
                                                millisecondsPer1KTokens: try optionalDecimal(value["millisecondsPer1KTokens"]),
                                                costCoverage: costCoverage, timingCoverage: timingCoverage)
    }

    private func commit(_ raw: Any) throws -> AnalyticsCommitAnalytics {
        let value = try object(raw)
        try keys(value, ["commitID", "committedAt", "correlatedUsage", "pullRequestNumber", "coverage"])
        let id = try requiredString(value, "commitID")
        guard id.range(of: #"^[0-9a-f]{12}$"#, options: .regularExpression) != nil else { throw AnalyticsDecodeSupport.fail([], "Invalid commit ID.") }
        let pr: Int?
        if value["pullRequestNumber"] is NSNull { pr = nil }
        else { guard let number = int(value["pullRequestNumber"]), number > 0, number <= 2_147_483_647 else { throw AnalyticsDecodeSupport.fail([], "Invalid PR number.") }; pr = number }
        let coverage = try requiredString(value, "coverage")
        guard AnalyticsDecodeSupport.commitCoverage.contains(coverage) else { throw AnalyticsDecodeSupport.fail([], "Unknown coverage.") }
        return AnalyticsCommitAnalytics(commitID: id, committedAt: try date(value["committedAt"]), correlatedUsage: try usage(value["correlatedUsage"]), pullRequestNumber: pr, coverage: coverage)
    }

    private func usage(_ raw: Any?) throws -> AnalyticsUsageAggregate {
        let value = try object(raw)
        try keys(value, ["inputTokens", "outputTokens", "cacheReadTokens", "cacheWriteTokens", "reasoningTokens", "totalTokens", "estimatedCostUSD"])
        let input = try integer(value["inputTokens"]); let output = try integer(value["outputTokens"])
        let read = try integer(value["cacheReadTokens"]); let write = try integer(value["cacheWriteTokens"])
        let reasoning = try integer(value["reasoningTokens"]); let total = try integer(value["totalTokens"])
        let cost = try requiredString(value, "estimatedCostUSD")
        guard AnalyticsDecodeSupport.canonicalCost(cost) != nil else { throw AnalyticsDecodeSupport.fail([], "Noncanonical cost.") }
        return AnalyticsUsageAggregate(inputTokens: input, outputTokens: output, cacheReadTokens: read, cacheWriteTokens: write, reasoningTokens: reasoning, totalTokens: total, estimatedCostUSD: cost)
    }

    private func attribution(_ raw: Any?) throws -> AnalyticsAttributionBucket {
        let value = try object(raw); try keys(value, ["usage", "fragments", "reasons"])
        return AnalyticsAttributionBucket(usage: try usage(value["usage"]), fragments: try count(value["fragments"]), reasons: try reasons(value["reasons"]))
    }
    private func analyticsCoverage(_ raw: Any?) throws -> AnalyticsCoverage {
        let value = try object(raw); try keys(value, ["attributedFragments", "unattributedFragments", "reasons"])
        return AnalyticsCoverage(attributedFragments: try count(value["attributedFragments"]), unattributedFragments: try count(value["unattributedFragments"]), reasons: try reasons(value["reasons"]))
    }
    private func repositoryCoverage(_ raw: Any?) throws -> RepositoryCoverage {
        let value = try object(raw); try keys(value, ["assignedFragments", "unassignedFragments", "timingPartial", "reasons"])
        guard let partial = value["timingPartial"] as? Bool else { throw AnalyticsDecodeSupport.fail([], "Invalid timing coverage.") }
        return RepositoryCoverage(assignedFragments: try count(value["assignedFragments"]), unassignedFragments: try count(value["unassignedFragments"]), timingPartial: partial, reasons: try reasons(value["reasons"]))
    }
    private func reasons(_ raw: Any?) throws -> [String: UInt64] {
        let value = try object(raw); var result: [String: UInt64] = [:]
        for (key, rawValue) in value { guard AnalyticsDecodeSupport.reasons.contains(key), result[key] == nil else { throw AnalyticsDecodeSupport.fail([], "Unknown or duplicate reason.") }; result[key] = try count(rawValue) }
        return result
    }
    private func errors(_ raw: Any?) throws -> [AnalyticsBridgeError] {
        guard let values = array(raw) else { throw AnalyticsDecodeSupport.fail([], "Invalid errors.") }
        let result = try values.map { raw in let value = try object(raw); try keys(value, ["scope", "code"]); let scope = try requiredString(value, "scope"); let code = try requiredString(value, "code"); guard AnalyticsDecodeSupport.scopes.contains(scope), AnalyticsDecodeSupport.errorCodes.contains(code) else { throw AnalyticsDecodeSupport.fail([], "Unknown analytics error.") }; return AnalyticsBridgeError(scope: scope, code: code) }
        for pair in zip(result, result.dropFirst()) { guard (pair.0.scope, pair.0.code) <= (pair.1.scope, pair.1.code) else { throw AnalyticsDecodeSupport.fail([], "Errors are not ordered.") } }
        return result
    }

    private func date(_ raw: Any?) throws -> Date {
        guard let value = raw as? String, value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$"#, options: .regularExpression) != nil else { throw AnalyticsDecodeSupport.fail([], "Expected UTC millisecond timestamp.") }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        guard let parsed = formatter.date(from: value) else { throw AnalyticsDecodeSupport.fail([], "Invalid timestamp.") }; return parsed
    }
    private func keys(_ value: [String: Any], _ allowed: Set<String>) throws { guard Set(value.keys) == allowed else { throw AnalyticsDecodeSupport.fail([], "Unknown or missing analytics field.") } }
    private func keys(_ value: [String: Any], _ allowed: [String]) throws { try keys(value, Set(allowed)) }
    private func object(_ raw: Any?) throws -> [String: Any] { guard let value = raw as? [String: Any] else { throw AnalyticsDecodeSupport.fail([], "Expected object.") }; return value }
    private func array(_ raw: Any?) -> [Any]? { raw as? [Any] }
    private func requiredArray(_ value: [String: Any], _ key: String) throws -> [Any] {
        guard let result = array(value[key]) else { throw AnalyticsDecodeSupport.fail([], "Expected required array.") }
        return result
    }
    private func string(_ value: [String: Any], _ key: String) -> String? { value[key] as? String }
    private func requiredString(_ value: [String: Any], _ key: String) throws -> String { guard let result = value[key] as? String else { throw AnalyticsDecodeSupport.fail([], "Expected string.") }; return result }
    private func integer(_ raw: Any?) throws -> String { guard let value = raw as? String, AnalyticsDecodeSupport.canonicalInteger(value) != nil else { throw AnalyticsDecodeSupport.fail([], "Expected canonical integer string.") }; return value }
    private func count(_ raw: Any?) throws -> UInt64 { guard let number = raw as? NSNumber, String(cString: number.objCType) != "c", String(cString: number.objCType) != "d", number.stringValue.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil, let value = UInt64(number.stringValue) else { throw AnalyticsDecodeSupport.fail([], "Expected nonnegative integer.") }; return value }
    private func int(_ raw: Any?) -> Int? { guard let number = raw as? NSNumber, String(cString: number.objCType) != "c", String(cString: number.objCType) != "d", number.stringValue.range(of: #"^(0|[1-9][0-9]*)$"#, options: .regularExpression) != nil else { return nil }; return Int(number.stringValue) }
    private func optionalDecimal(_ raw: Any?) throws -> String? { if raw is NSNull { return nil }; let value = try requiredString(["value": raw as Any], "value"); guard AnalyticsDecodeSupport.canonicalCost(value) != nil else { throw AnalyticsDecodeSupport.fail([], "Invalid metric.") }; return value }
}
