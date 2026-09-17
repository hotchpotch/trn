import Foundation
import Testing
@testable import TranslateCore

private struct RecordingTranslator: TextTranslating {
    let translateHandler: @Sendable (TranslationRequest) async throws -> TranslationResult

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await translateHandler(request)
    }
}

@Suite("Command runner")
struct CommandRunnerTests {
    @Test("translates with a mockable translator")
    func translatesWithMockableTranslator() async {
        let translator = RecordingTranslator { request in
            #expect(request.sourceText == "こんにちは")
            #expect(request.sourceLanguageCode == "ja")
            #expect(request.targetLanguageCode == "en")
            #expect(request.quality == .low)
            return TranslationResult(
                sourceLanguageCode: request.sourceLanguageCode,
                targetLanguageCode: request.targetLanguageCode,
                sourceText: request.sourceText,
                targetText: "Hello"
            )
        }
        let runner = CommandRunner(translator: translator)

        let result = await runner.run(arguments: ["--to", "en", "こんにちは"], stdin: nil)

        #expect(result == CommandResult(output: "Hello\n", errorOutput: "", exitCode: 0))
    }

    @Test("passes requested translation quality to translator")
    func passesRequestedTranslationQuality() async {
        let translator = RecordingTranslator { request in
            #expect(request.quality == .low)
            return TranslationResult(
                sourceLanguageCode: request.sourceLanguageCode,
                targetLanguageCode: request.targetLanguageCode,
                sourceText: request.sourceText,
                targetText: "Hello"
            )
        }
        let runner = CommandRunner(translator: translator)

        let result = await runner.run(arguments: ["--to", "en", "--quality", "low", "こんにちは"], stdin: nil)

        #expect(result == CommandResult(output: "Hello\n", errorOutput: "", exitCode: 0))
    }

    @Test("preserves region codes and high quality in translation requests")
    func preservesRegionCodes() async {
        let translator = RecordingTranslator { request in
            #expect(request.sourceLanguageCode == "en-GB")
            #expect(request.targetLanguageCode == "zh-TW")
            #expect(request.quality == .high)
            return TranslationResult(sourceLanguageCode: request.sourceLanguageCode, targetLanguageCode: request.targetLanguageCode, sourceText: request.sourceText, targetText: "translated")
        }
        let result = await CommandRunner(translator: translator).run(arguments: ["--from", "en-GB", "--to", "zh-TW", "-q", "high", "hello"], stdin: nil)
        #expect(result.output == "translated\n")
        #expect(result.exitCode == 0)
    }

    @Test("returns usage on failure")
    func returnsUsageOnFailure() async {
        let runner = CommandRunner(translator: MockTranslator())

        let result = await runner.run(arguments: ["こんにちは"], stdin: nil)

        #expect(result.exitCode == 1)
        #expect(result.output == "")
        #expect(result.errorOutput.contains("trn 0.2.0"))
        #expect(result.errorOutput.contains("usage: trn"))
    }

    @Test("prints help with version")
    func printsHelpWithVersion() async {
        let runner = CommandRunner(translator: MockTranslator())

        let result = await runner.run(arguments: ["--help"], stdin: nil)

        #expect(result.exitCode == 0)
        #expect(result.errorOutput == "")
        #expect(result.output.contains("trn 0.2.0"))
        #expect(result.output.contains("usage: trn"))
    }

    @Test("prints version")
    func printsVersion() async {
        let runner = CommandRunner(translator: MockTranslator())

        let result = await runner.run(arguments: ["--version"], stdin: nil)

        #expect(result == CommandResult(output: "trn 0.2.0\n", errorOutput: "", exitCode: 0))
    }

    @Test("returns original text when source and target are the same")
    func returnsOriginalForSameLanguage() async {
        let runner = CommandRunner(translator: MockTranslator())

        let result = await runner.run(arguments: ["--to", "en", "hello"], stdin: nil)

        #expect(result == CommandResult(output: "hello\n", errorOutput: "", exitCode: 0))
    }

    @Test("same-language region variants return the original text")
    func regionVariantsPassThrough() async {
        let translator = RecordingTranslator { _ in
            Issue.record("Same language must not call translator")
            throw CancellationError()
        }
        for (source, target) in [("en-GB", "en"), ("ar-AE", "ar")] {
            let result = await CommandRunner(translator: translator).run(arguments: ["--from", source, "--to", target, "hello"], stdin: nil)
            #expect(result.output == "hello\n")
            #expect(result.exitCode == 0)
        }
    }

    @Test("different Chinese scripts still call the translator")
    func distinctScriptsTranslate() async {
        let translator = RecordingTranslator { request in
            #expect(request.sourceLanguageCode == "zh")
            #expect(request.targetLanguageCode == "zh-TW")
            return TranslationResult(sourceLanguageCode: "zh", targetLanguageCode: "zh-TW", sourceText: request.sourceText, targetText: "translated")
        }
        let result = await CommandRunner(translator: translator).run(arguments: ["--from", "zh", "--to", "zh-TW", "hello"], stdin: nil)
        #expect(result.output == "translated\n")
    }

    @Test("streams chunks concurrently while preserving output order")
    func streamsConcurrentlyInOrder() async {
        let probe = StreamProbe()
        let translator = ProbeTranslator(probe: probe)
        let runner = CommandRunner(translator: translator)

        let result = await runner.run(arguments: ["--from", "ja", "--to", "en", "-q", "low", "--buffer-size", "5", "--concurrency", "2", "a\nbbbb\ncc\nddd"], stdin: nil)

        #expect(result == CommandResult(output: "<a>\n<bbbb>\n<cc>\n<ddd>\n", errorOutput: "", exitCode: 0))
        #expect(await probe.maxActive <= 2)
        #expect(Set(await probe.requestedTexts) == Set(["a", "bbbb", "cc", "ddd"]))
        #expect(Set(await probe.qualities) == Set([.low]))
    }

    @Test("streams use one auto-detected source language for all chunks")
    func streamsUseOneAutoDetectedSourceLanguage() async {
        let probe = StreamProbe()
        let translator = ProbeTranslator(probe: probe)
        let runner = CommandRunner(translator: translator)

        let result = await runner.run(arguments: ["--to", "en", "--buffer-size", "6", "--concurrency", "2", "こんにちは\na\nb"], stdin: nil)

        #expect(result == CommandResult(output: "<こんにちは>\n<a\nb>\n", errorOutput: "", exitCode: 0))
        #expect(Set(await probe.sourceLanguageCodes) == Set(["ja"]))
        #expect(Set(await probe.requestedTexts) == Set(["こんにちは", "a\nb"]))
    }
}

private actor StreamProbe {
    private var active = 0
    private(set) var maxActive = 0
    private(set) var requestedTexts: [String] = []
    private(set) var sourceLanguageCodes: [String] = []
    private(set) var qualities: [TranslationQuality] = []

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        active += 1
        maxActive = max(maxActive, active)
        requestedTexts.append(request.sourceText)
        sourceLanguageCodes.append(request.sourceLanguageCode)
        qualities.append(request.quality)

        let delay = UInt64(max(1, 6 - request.sourceText.count)) * 1_000_000
        try await Task.sleep(nanoseconds: delay)

        active -= 1
        return TranslationResult(
            sourceLanguageCode: request.sourceLanguageCode,
            targetLanguageCode: request.targetLanguageCode,
            sourceText: request.sourceText,
            targetText: "<\(request.sourceText)>"
        )
    }
}

private struct ProbeTranslator: TextTranslating {
    let probe: StreamProbe

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
        try await probe.translate(request)
    }
}
