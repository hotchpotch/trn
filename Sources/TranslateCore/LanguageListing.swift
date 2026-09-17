import Foundation
import Translation

public struct LanguageListOptions: Equatable, Sendable {
    public let targetLanguage: String?
    public let quality: TranslationQuality

    public init(targetLanguage: String? = nil, quality: TranslationQuality = .low) {
        self.targetLanguage = targetLanguage
        self.quality = quality
    }
}

public enum LanguagePairStatus: String, Encodable, Sendable {
    case installed
    case supported
    case unsupported
    case unknown
    case sameLanguage = "same_language"
}

public protocol LanguageAvailabilityProviding: Sendable {
    func supportedLanguages(quality: TranslationQuality) async -> [String]
    func status(from source: String, to target: String, quality: TranslationQuality) async -> LanguagePairStatus
}

public struct AppleLanguageAvailability: LanguageAvailabilityProviding {
    public init() {}

    public func supportedLanguages(quality: TranslationQuality) async -> [String] {
        let availability = LanguageAvailability(preferredStrategy: .init(quality: quality))
        return await availability.supportedLanguages.map(\.minimalIdentifier)
    }

    public func status(from source: String, to target: String, quality: TranslationQuality) async -> LanguagePairStatus {
        let availability = LanguageAvailability(preferredStrategy: .init(quality: quality))
        switch await availability.status(from: Locale.Language(identifier: source), to: Locale.Language(identifier: target)) {
        case .installed: return .installed
        case .supported: return .supported
        case .unsupported: return .unsupported
        @unknown default: return .unknown
        }
    }
}

struct LanguageListing {
    let provider: any LanguageAvailabilityProviding
    let resolver: LanguageResolver

    func json(options: LanguageListOptions) async throws -> String {
        let target = try options.targetLanguage.map { try resolver.resolveTarget($0) }
        let codes = await provider.supportedLanguages(quality: options.quality)
        var rows: [LanguageRow] = []
        for code in Set(codes).sorted() {
            let status: LanguagePairStatus?
            if let target {
                status = resolver.isSameLanguage(code, target) ? .sameLanguage : await provider.status(from: code, to: target, quality: options.quality)
            } else {
                status = nil
            }
            rows.append(LanguageRow(code: code, name: Locale(identifier: "en").localizedString(forIdentifier: code) ?? code, status: status))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(LanguageList(quality: options.quality.rawValue, target: target, languages: rows))
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}

private struct LanguageList: Encodable {
    let quality: String
    let target: String?
    let languages: [LanguageRow]
}

private struct LanguageRow: Encodable {
    let code: String
    let name: String
    let status: LanguagePairStatus?
}
