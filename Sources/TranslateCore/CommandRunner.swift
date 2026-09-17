import Foundation

public typealias OutputEmitter = (String) async -> Void

public struct CommandResult: Equatable, Sendable {
    public let output: String
    public let errorOutput: String
    public let exitCode: Int32

    public init(output: String, errorOutput: String, exitCode: Int32) {
        self.output = output
        self.errorOutput = errorOutput
        self.exitCode = exitCode
    }
}

public struct CommandRunner<Translator: TextTranslating>: Sendable {
    private let parser: CLIParser
    private let inputResolver: InputResolver
    private let languageResolver: LanguageResolver
    private let translator: Translator
    private let languageAvailability: any LanguageAvailabilityProviding

    public init(
        parser: CLIParser = CLIParser(),
        inputResolver: InputResolver = InputResolver(),
        languageResolver: LanguageResolver = LanguageResolver(),
        translator: Translator,
        languageAvailability: any LanguageAvailabilityProviding = AppleLanguageAvailability()
    ) {
        self.parser = parser
        self.inputResolver = inputResolver
        self.languageResolver = languageResolver
        self.translator = translator
        self.languageAvailability = languageAvailability
    }

    public func run(arguments: [String], stdin: String?) async -> CommandResult {
        let outputBuffer = OutputBuffer()
        let result = await run(arguments: arguments, stdin: stdin) { chunk in
            await outputBuffer.append(chunk)
        }
        let streamedOutput = await outputBuffer.text
        return CommandResult(
            output: result.output + streamedOutput,
            errorOutput: result.errorOutput,
            exitCode: result.exitCode
        )
    }

    public func run(arguments: [String], stdin: String?, emit: OutputEmitter) async -> CommandResult {
        do {
            let command = try parser.parseCommand(arguments)
            switch command {
            case .help:
                return CommandResult(output: helpOutput, errorOutput: "", exitCode: 0)
            case .version:
                return CommandResult(output: versionOutput, errorOutput: "", exitCode: 0)
            case let .listLanguages(options):
                let output = try await LanguageListing(provider: languageAvailability, resolver: languageResolver).json(options: options)
                return CommandResult(output: output, errorOutput: "", exitCode: 0)
            case let .translate(options):
                return try await runTranslation(options: options, stdin: stdin, emit: emit)
            }
        } catch {
            let message = "\(error)\n\n\(helpOutput)"
            return CommandResult(output: "", errorOutput: message, exitCode: 1)
        }
    }

    private func runTranslation(options: CLIOptions, stdin: String?, emit: OutputEmitter) async throws -> CommandResult {
        let text = try inputResolver.resolve(options: options, stdin: stdin)
        if options.streamMode == .paragraph {
            try await runStream(options: options, text: text, emit: emit)
            return CommandResult(output: "", errorOutput: "", exitCode: 0)
        }

        let request = TranslationRequest(
            sourceText: text,
            sourceLanguageCode: try languageResolver.resolveSource(options.sourceLanguage, text: text),
            targetLanguageCode: try languageResolver.resolveTarget(options.targetLanguage),
            quality: options.quality
        )
        guard !languageResolver.isSameLanguage(request.sourceLanguageCode, request.targetLanguageCode) else {
            return CommandResult(output: text + "\n", errorOutput: "", exitCode: 0)
        }

        let result = try await translator.translate(request)
        return CommandResult(output: result.targetText + "\n", errorOutput: "", exitCode: 0)
    }

    private func runStream(options: CLIOptions, text: String, emit: OutputEmitter) async throws {
        let targetLanguageCode = try languageResolver.resolveTarget(options.targetLanguage)
        let sourceLanguageCode = try languageResolver.resolveSource(options.sourceLanguage, text: text)
        let segments = ParagraphSegmenter(maxCharacters: options.bufferSize).segments(from: text)
        guard !segments.isEmpty else {
            await emit("\n")
            return
        }

        try await withThrowingTaskGroup(of: IndexedStreamOutput.self) { group in
            var nextToSchedule = 0
            var nextToEmit = 0
            var completedOutputs: [Int: String] = [:]

            while nextToSchedule < min(options.concurrency, segments.count) {
                let segment = segments[nextToSchedule]
                group.addTask {
                    try await translateStreamSegment(
                        segment,
                        sourceLanguageCode: sourceLanguageCode,
                        targetLanguageCode: targetLanguageCode,
                        quality: options.quality
                    )
                }
                nextToSchedule += 1
            }

            while let completed = try await group.next() {
                completedOutputs[completed.index] = completed.output

                while let readyOutput = completedOutputs.removeValue(forKey: nextToEmit) {
                    await emit(readyOutput)
                    nextToEmit += 1
                }

                if nextToSchedule < segments.count {
                    let segment = segments[nextToSchedule]
                    group.addTask {
                        try await translateStreamSegment(
                            segment,
                            sourceLanguageCode: sourceLanguageCode,
                            targetLanguageCode: targetLanguageCode,
                            quality: options.quality
                        )
                    }
                    nextToSchedule += 1
                }
            }
        }
    }

    private func translateStreamSegment(
        _ segment: StreamSegment,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        quality: TranslationQuality
    ) async throws -> IndexedStreamOutput {
        guard !segment.sourceText.isEmpty else {
            return IndexedStreamOutput(index: segment.index, output: segment.outputSuffix)
        }

        guard !languageResolver.isSameLanguage(sourceLanguageCode, targetLanguageCode) else {
            return IndexedStreamOutput(index: segment.index, output: segment.sourceText + segment.outputSuffix)
        }

        let result = try await translator.translate(
            TranslationRequest(
                sourceText: segment.sourceText,
                sourceLanguageCode: sourceLanguageCode,
                targetLanguageCode: targetLanguageCode,
                quality: quality
            )
        )
        return IndexedStreamOutput(index: segment.index, output: result.targetText + segment.outputSuffix)
    }
}

private struct IndexedStreamOutput: Sendable {
    let index: Int
    let output: String
}

private actor OutputBuffer {
    private(set) var text = ""

    func append(_ chunk: String) {
        text += chunk
    }
}
