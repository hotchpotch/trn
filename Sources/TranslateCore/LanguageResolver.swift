import Foundation
import NaturalLanguage

public enum LanguageResolverError: Error, Equatable, CustomStringConvertible {
    case unsupportedLanguage(String)
    case unableToDetectLanguage

    public var description: String {
        switch self {
        case let .unsupportedLanguage(language):
            "unsupported language: \(language)"
        case .unableToDetectLanguage:
            "unable to detect source language"
        }
    }
}

public struct TranslationRequest: Equatable, Sendable {
    public let sourceText: String
    public let sourceLanguageCode: String
    public let targetLanguageCode: String
    public let quality: TranslationQuality

    public init(
        sourceText: String,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        quality: TranslationQuality = .low
    ) {
        self.sourceText = sourceText
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.quality = quality
    }
}

public struct LanguageResolver: Sendable {
    private let aliases: [String: String]

    public init(aliases: [String: String] = LanguageResolver.defaultAliases) {
        self.aliases = aliases
    }

    public func resolveTarget(_ language: String) throws -> String {
        try resolve(language)
    }

    public func resolveSource(_ language: String?, text: String) throws -> String {
        if let language {
            return try resolve(language)
        }

        guard let detected = NLLanguageRecognizer.dominantLanguage(for: text),
              detected != .undetermined
        else {
            throw LanguageResolverError.unableToDetectLanguage
        }

        return try resolve(detected.rawValue)
    }

    // Region variants share a language only when their effective scripts also match.
    func isSameLanguage(_ source: String, _ target: String) -> Bool {
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        return sourceLanguage.languageCode == targetLanguage.languageCode
            && sourceLanguage.script == targetLanguage.script
    }

    private func resolve(_ language: String) throws -> String {
        let normalized = language
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")

        if let alias = aliases[normalized] {
            return alias
        }

        // Accept language[-Script][-REGION], including numeric UN M49 regions.
        // Validate before Foundation normalization, which can silently discard malformed text.
        if normalized.range(of: "^[a-z]{2,3}(-[a-z]{4})?(-([a-z]{2}|[0-9]{3}))?$", options: .regularExpression) != nil {
            let candidate = Locale.Language(identifier: normalized)
            guard candidate.languageCode?.identifier != "und" else {
                throw LanguageResolverError.unsupportedLanguage(language)
            }
            return candidate.minimalIdentifier
        }

        throw LanguageResolverError.unsupportedLanguage(language)
    }

    public static let defaultAliases: [String: String] = [
        "arabic": "ar",
        "ar": "ar",
        "chinese": "zh",
        "zh": "zh",
        "english": "en",
        "en": "en",
        "french": "fr",
        "fr": "fr",
        "german": "de",
        "de": "de",
        "italian": "it",
        "it": "it",
        "japanese": "ja",
        "ja": "ja",
        "korean": "ko",
        "ko": "ko",
        "portuguese": "pt",
        "pt": "pt",
        "russian": "ru",
        "ru": "ru",
        "spanish": "es",
        "es": "es"
    ]
}
