import Foundation
import Testing
@testable import TranslateCore

@Suite("Language listing")
struct LanguageListingTests {
    @Test func parsesListing() throws {
        #expect(try CLIParser().parseCommand(["--list-languages", "--help"]) == .help)
        #expect(try CLIParser().parseCommand(["-h", "--list-languages"]) == .help)
        #expect(try CLIParser().parseCommand(["--list-languages"]) == .listLanguages(.init()))
        #expect(try CLIParser().parseCommand(["--quality", "high", "--list-languages", "--to", "english"]) == .listLanguages(.init(targetLanguage: "english", quality: .high)))
    }

    @Test(arguments: [["--list-languages", "hello"], ["--list-languages", "--from", "ja"], ["--list-languages", "--stream"], ["--list-languages", "--quality", "medium"], ["--list-languages", "--to"]])
    func rejectsInvalidArguments(arguments: [String]) {
        #expect(throws: (any Error).self) { try CLIParser().parseCommand(arguments) }
    }

    @Test func shortHelpCanStillBeTranslated() throws {
        let command = try CLIParser().parseCommand(["--to", "en", "-h"])
        #expect(command == .translate(CLIOptions(targetLanguage: "en", sourceLanguage: nil, positionalText: "-h")))
    }

    @Test(arguments: ["-q", "-b"])
    func missingValueBeforeShortOption(option: String) {
        #expect(throws: CLIParseError.missingValue("--to")) {
            try CLIParser().parseCommand(["--list-languages", "--to", option])
        }
    }

    @Test func serializesOtherStatusesAndNames() async throws {
        let runner = CommandRunner(translator: UnusedTranslator(), languageAvailability: StatusMock())
        let result = await runner.run(arguments: ["--list-languages", "--to", "ja"], stdin: nil)
        #expect(result.exitCode == 0)
        let json = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        let rows = try #require(json["languages"] as? [[String: String]])
        #expect(rows == [
            ["code": "en-GB", "name": "English (United Kingdom)", "status": "unsupported"],
            ["code": "xx", "name": "xx", "status": "unknown"]
        ])
    }

    @Test func preservesLanguageVariants() throws {
        let resolver = LanguageResolver()
        #expect(try resolver.resolveTarget(" EN_gb ") == "en-GB")
        #expect(try resolver.resolveTarget("zh-TW") == "zh-TW")
        #expect(try resolver.resolveSource("zh-Hant", text: "") == "zh-TW")
    }

    @Test(arguments: ["und", "und-US", "und-JP", "123", "en-@@", "en--GB", "en-", "en-US-extra", "en-1234"])
    func rejectsMalformedLanguageCodes(code: String) async {
        #expect(throws: LanguageResolverError.unsupportedLanguage(code)) {
            try LanguageResolver().resolveTarget(code)
        }
        let runner = CommandRunner(translator: UnusedTranslator(), languageAvailability: ListingMock(expectedQuality: .low))
        let result = await runner.run(arguments: ["--list-languages", "--to", code], stdin: nil)
        #expect(result.exitCode == 1)
        #expect(result.output.isEmpty)
    }

    @Test func sameLanguageRespectsScript() throws {
        let resolver = LanguageResolver()
        #expect(resolver.isSameLanguage(try resolver.resolveTarget("en-GB"), try resolver.resolveTarget("en")))
        #expect(resolver.isSameLanguage(try resolver.resolveTarget("ar-AE"), try resolver.resolveTarget("ar")))
        #expect(resolver.isSameLanguage(try resolver.resolveTarget("zh-Hant"), try resolver.resolveTarget("zh-TW")))
        #expect(!resolver.isSameLanguage(try resolver.resolveTarget("zh"), try resolver.resolveTarget("zh-TW")))
        #expect(!resolver.isSameLanguage(try resolver.resolveTarget("sr-Cyrl"), try resolver.resolveTarget("sr-Latn")))
        #expect(!resolver.isSameLanguage(try resolver.resolveTarget("en"), try resolver.resolveTarget("ja")))
    }

    @Test func acceptsScriptRegionAndUnsupportedCodes() throws {
        let resolver = LanguageResolver()
        #expect(try resolver.resolveTarget("zh_Hant_TW") == "zh-TW")
        #expect(try resolver.resolveTarget("es-419") == "es-419")
        #expect(try resolver.resolveTarget("eo") == "eo")
    }

    @Test func invalidTargetProducesOnlyError() async {
        let runner = CommandRunner(translator: UnusedTranslator(), languageAvailability: ListingMock(expectedQuality: .low))
        let result = await runner.run(arguments: ["--list-languages", "--to", "invalid"], stdin: nil)
        #expect(result.exitCode == 1)
        #expect(result.output.isEmpty)
        #expect(result.errorOutput.contains("unsupported language: invalid"))
    }

    @Test(arguments: [TranslationQuality.low, .high])
    func listsJSON(quality: TranslationQuality) async throws {
        let provider = ListingMock(expectedQuality: quality)
        let runner = CommandRunner(translator: UnusedTranslator(), languageAvailability: provider)
        let result = await runner.run(arguments: ["--list-languages", "-q", quality.rawValue], stdin: "ignored")
        #expect(result.exitCode == 0)
        let json = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        #expect(json["quality"] as? String == quality.rawValue)
        #expect(json["target"] == nil)
        let rows = try #require(json["languages"] as? [[String: String]])
        #expect(rows.map { $0["code"]! } == ["en", "en-GB", "ja"])
        #expect(rows.allSatisfy { $0["status"] == nil })
    }

    @Test(arguments: [TranslationQuality.low, .high])
    func listsPairStatus(quality: TranslationQuality) async throws {
        let runner = CommandRunner(translator: UnusedTranslator(), languageAvailability: ListingMock(expectedQuality: quality))
        let result = await runner.run(arguments: ["--list-languages", "--to", "english", "-q", quality.rawValue], stdin: nil)
        #expect(result.exitCode == 0)
        let json = try #require(JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        #expect(json["target"] as? String == "en")
        let rows = try #require(json["languages"] as? [[String: String]])
        #expect(rows.map { $0["status"]! } == ["same_language", "same_language", quality == .low ? "supported" : "installed"])
    }
}

private struct ListingMock: LanguageAvailabilityProviding {
    let expectedQuality: TranslationQuality
    func supportedLanguages(quality: TranslationQuality) async -> [String] {
        #expect(quality == expectedQuality)
        return ["ja", "en-GB", "en"]
    }
    func status(from source: String, to target: String, quality: TranslationQuality) async -> LanguagePairStatus {
        #expect(quality == expectedQuality)
        #expect(target == "en")
        #expect(source == "ja")
        return quality == .low ? .supported : .installed
    }
}

private struct UnusedTranslator: TextTranslating {
    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        Issue.record("Listing must not translate")
        throw CancellationError()
    }
}

private struct StatusMock: LanguageAvailabilityProviding {
    func supportedLanguages(quality: TranslationQuality) async -> [String] { ["xx", "en-GB"] }
    func status(from source: String, to target: String, quality: TranslationQuality) async -> LanguagePairStatus {
        source == "xx" ? .unknown : .unsupported
    }
}
