import Foundation

public struct ThingPhotoLabelingEvaluationCase: Hashable, Sendable {
    public enum ExpectedOutcome: String, Hashable, Sendable {
        case suggestion
        case refusal
        case manualFallback
    }

    public let id: String
    public let expectedOutcome: ExpectedOutcome
    public let acceptedNames: [String]
    public let expectedKeywords: [String]
    public let expectedDetailTerms: [String]
    public let prohibitedTerms: [String]
    public let expectedFallbackError: ThingPhotoLabelingEvaluationFallback?
    public let maximumLatencyMilliseconds: Int

    public init(
        id: String,
        expectedOutcome: ExpectedOutcome,
        acceptedNames: [String] = [],
        expectedKeywords: [String] = [],
        expectedDetailTerms: [String] = [],
        prohibitedTerms: [String] = [],
        expectedFallbackError: ThingPhotoLabelingEvaluationFallback? = nil,
        maximumLatencyMilliseconds: Int
    ) {
        self.id = id
        self.expectedOutcome = expectedOutcome
        self.acceptedNames = acceptedNames
        self.expectedKeywords = expectedKeywords
        self.expectedDetailTerms = expectedDetailTerms
        self.prohibitedTerms = prohibitedTerms
        self.expectedFallbackError = expectedFallbackError
        self.maximumLatencyMilliseconds = maximumLatencyMilliseconds
    }
}

public enum ThingPhotoLabelingEvaluationFallback: String, Hashable, Sendable {
    case offline
    case rateLimited
    case timedOut
    case unavailable

    init(error: ThingPhotoLabelingError) {
        switch error {
        case .connectionUnavailable:
            self = .offline
        case .rateLimited:
            self = .rateLimited
        case .timedOut:
            self = .timedOut
        default:
            self = .unavailable
        }
    }
}

public enum ThingPhotoLabelingEvaluationObservation: Equatable, Sendable {
    case suggestion(ThingLabelSuggestion)
    case refusal
    case manualFallback(ThingPhotoLabelingError)
}

public struct ThingPhotoLabelingEvaluationScore: Hashable, Sendable {
    public enum Dimension: String, CaseIterable, Hashable, Sendable {
        case naming
        case keywords
        case details
        case refusal
        case irrelevantText
        case manualFallback
        case latency
    }

    public let caseID: String
    public let values: [Dimension: Double]

    public var passed: Bool {
        values.values.allSatisfy { $0 == 1 }
    }

    public init(caseID: String, values: [Dimension: Double]) {
        self.caseID = caseID
        self.values = values
    }
}

public enum ThingPhotoLabelingEvaluator {
    public static func score(
        _ observation: ThingPhotoLabelingEvaluationObservation,
        latencyMilliseconds: Int,
        against evaluationCase: ThingPhotoLabelingEvaluationCase
    ) -> ThingPhotoLabelingEvaluationScore {
        var values: [ThingPhotoLabelingEvaluationScore.Dimension: Double] = [
            .latency: latencyMilliseconds <= evaluationCase.maximumLatencyMilliseconds ? 1 : 0
        ]

        switch evaluationCase.expectedOutcome {
        case .suggestion:
            values[.refusal] = 1
            values[.manualFallback] = 1
            guard case let .suggestion(suggestion) = observation else {
                values[.naming] = 0
                values[.keywords] = 0
                values[.details] = 0
                values[.irrelevantText] = 0
                return .init(caseID: evaluationCase.id, values: values)
            }
            values[.naming] = bestNameScore(
                suggestion.proposedName,
                acceptedNames: evaluationCase.acceptedNames
            )
            values[.keywords] = setF1(
                actual: suggestion.keywords,
                expected: evaluationCase.expectedKeywords
            )
            values[.details] = detailScore(
                suggestion.detail,
                expectedTerms: evaluationCase.expectedDetailTerms
            )
            values[.irrelevantText] = containsProhibitedText(
                suggestion,
                prohibitedTerms: evaluationCase.prohibitedTerms
            ) ? 0 : 1
        case .refusal:
            values[.refusal] = observation == .refusal ? 1 : 0
            values[.irrelevantText] = observationContainsProhibitedText(
                observation,
                prohibitedTerms: evaluationCase.prohibitedTerms
            ) ? 0 : 1
        case .manualFallback:
            if case let .manualFallback(error) = observation {
                let actual = ThingPhotoLabelingEvaluationFallback(error: error)
                values[.manualFallback] = evaluationCase.expectedFallbackError
                    .map { $0 == actual ? 1 : 0 } ?? 1
            } else {
                values[.manualFallback] = 0
            }
            values[.irrelevantText] = observationContainsProhibitedText(
                observation,
                prohibitedTerms: evaluationCase.prohibitedTerms
            ) ? 0 : 1
        }

        return .init(caseID: evaluationCase.id, values: values)
    }

    private static func bestNameScore(_ actual: String, acceptedNames: [String]) -> Double {
        guard !acceptedNames.isEmpty else {
            return normalized(actual).isEmpty ? 0 : 1
        }
        return acceptedNames.map { candidate in
            setF1(actual: tokens(actual), expected: tokens(candidate))
        }.max() ?? 0
    }

    private static func detailScore(_ actual: String?, expectedTerms: [String]) -> Double {
        guard !expectedTerms.isEmpty else {
            return 1
        }
        let normalizedDetail = normalized(actual ?? "")
        let matches = expectedTerms.filter { normalizedDetail.contains(normalized($0)) }.count
        return Double(matches) / Double(expectedTerms.count)
    }

    private static func setF1(actual: [String], expected: [String]) -> Double {
        let actualSet = Set(actual.map { normalized($0) }.filter { !$0.isEmpty })
        let expectedSet = Set(expected.map { normalized($0) }.filter { !$0.isEmpty })
        if actualSet.isEmpty && expectedSet.isEmpty {
            return 1
        }
        guard !actualSet.isEmpty, !expectedSet.isEmpty else {
            return 0
        }
        let intersection = actualSet.intersection(expectedSet).count
        let precision = Double(intersection) / Double(actualSet.count)
        let recall = Double(intersection) / Double(expectedSet.count)
        guard precision + recall > 0 else {
            return 0
        }
        return 2 * precision * recall / (precision + recall)
    }

    private static func tokens(_ value: String) -> [String] {
        normalized(value).split(separator: " ").map(String.init)
    }

    private static func containsProhibitedText(
        _ suggestion: ThingLabelSuggestion,
        prohibitedTerms: [String]
    ) -> Bool {
        let output = normalized(
            ([suggestion.proposedName] + suggestion.keywords + [suggestion.detail ?? ""])
                .joined(separator: " ")
        )
        return prohibitedTerms.contains { output.contains(normalized($0)) }
    }

    private static func observationContainsProhibitedText(
        _ observation: ThingPhotoLabelingEvaluationObservation,
        prohibitedTerms: [String]
    ) -> Bool {
        guard case let .suggestion(suggestion) = observation else {
            return false
        }
        return containsProhibitedText(suggestion, prohibitedTerms: prohibitedTerms)
    }

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
