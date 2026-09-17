import Foundation
import Translation

public enum AppleTranslatorError: Error, CustomStringConvertible {
    case unsupportedPair(source: String, target: String)
    case languagePackageNotInstalled(source: String, target: String)

    public var description: String {
        switch self {
        case let .unsupportedPair(source, target):
            "unsupported language pair: \(source) -> \(target)"
        case let .languagePackageNotInstalled(source, target):
            "language package is not installed: \(source) -> \(target). Open System Settings > General > Language & Region > Translation Languages, install the required languages, then retry."
        }
    }
}

public struct AppleTranslator: TextTranslating {
    public init() {}

    public func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        let source = Locale.Language(identifier: request.sourceLanguageCode)
        let target = Locale.Language(identifier: request.targetLanguageCode)
        let strategy = TranslationSession.Strategy(quality: request.quality)
        let availability = LanguageAvailability(preferredStrategy: strategy)
        let status = await availability.status(from: source, to: target)

        switch status {
        case .unsupported:
            throw AppleTranslatorError.unsupportedPair(
                source: request.sourceLanguageCode,
                target: request.targetLanguageCode
            )
        case .supported:
            throw AppleTranslatorError.languagePackageNotInstalled(
                source: request.sourceLanguageCode,
                target: request.targetLanguageCode
            )
        case .installed:
            let session = TranslationSession(installedSource: source, target: target, preferredStrategy: strategy)
            let response = try await session.translate(request.sourceText)
            return TranslationResult(
                sourceLanguageCode: response.sourceLanguage.languageCode?.identifier ?? request.sourceLanguageCode,
                targetLanguageCode: response.targetLanguage.languageCode?.identifier ?? request.targetLanguageCode,
                sourceText: response.sourceText,
                targetText: response.targetText
            )
        @unknown default:
            throw AppleTranslatorError.unsupportedPair(
                source: request.sourceLanguageCode,
                target: request.targetLanguageCode
            )
        }
    }
}

extension TranslationSession.Strategy {
    init(quality: TranslationQuality) {
        switch quality {
        case .high:
            self = .highFidelity
        case .low:
            self = .lowLatency
        }
    }
}
