import Foundation

public struct CLIOptions: Equatable, Sendable {
    public let targetLanguage: String
    public let sourceLanguage: String?
    public let positionalText: String?
    public let streamMode: StreamMode
    public let concurrency: Int
    public let bufferSize: Int
    public let quality: TranslationQuality

    public init(
        targetLanguage: String,
        sourceLanguage: String?,
        positionalText: String?,
        streamMode: StreamMode = .paragraph,
        concurrency: Int = 4,
        bufferSize: Int = 512,
        quality: TranslationQuality = .low
    ) {
        self.targetLanguage = targetLanguage
        self.sourceLanguage = sourceLanguage
        self.positionalText = positionalText
        self.streamMode = streamMode
        self.concurrency = concurrency
        self.bufferSize = bufferSize
        self.quality = quality
    }
}

public enum StreamMode: Equatable, Sendable {
    case disabled
    case paragraph
}

public enum CLICommand: Equatable, Sendable {
    case help
    case version
    case translate(CLIOptions)
    case listLanguages(LanguageListOptions)
}

public enum CLIParseError: Error, Equatable, CustomStringConvertible {
    case missingRequiredTo
    case missingValue(String)
    case invalidValue(String, String)
    case unknownOption(String)
    case tooManyPositionalArguments

    public var description: String {
        switch self {
        case .missingRequiredTo:
            "missing required option: --to"
        case let .missingValue(option):
            "missing value for \(option)"
        case let .invalidValue(option, value):
            "invalid value for \(option): \(value)"
        case let .unknownOption(option):
            "unknown option: \(option)"
        case .tooManyPositionalArguments:
            "too many positional arguments"
        }
    }
}

public struct CLIParser: Sendable {
    public init() {}

    public func parseCommand(_ arguments: [String]) throws -> CLICommand {
        if arguments.contains("--help") || (arguments.contains("--list-languages") && arguments.contains("-h")) {
            return .help
        }
        if arguments.count == 1 {
            switch arguments[0] {
            case "-h", "--help":
                return .help
            case "--version":
                return .version
            default:
                break
            }
        }

        if arguments.contains("--list-languages") {
            return .listLanguages(try parseLanguageList(arguments))
        }
        return .translate(try parse(arguments))
    }

    private func parseLanguageList(_ arguments: [String]) throws -> LanguageListOptions {
        var target: String?
        var quality = TranslationQuality.low
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--list-languages":
                index += 1
            case "--to":
                target = try value(after: argument, in: arguments, index: &index)
            case "-q", "--quality":
                let raw = try value(after: argument, in: arguments, index: &index)
                guard let parsed = TranslationQuality(rawValue: raw.lowercased()) else {
                    throw CLIParseError.invalidValue(argument, raw)
                }
                quality = parsed
            default:
                throw CLIParseError.unknownOption(argument)
            }
        }
        return LanguageListOptions(targetLanguage: target, quality: quality)
    }

    public func parse(_ arguments: [String]) throws -> CLIOptions {
        var targetLanguage: String?
        var sourceLanguage: String?
        var streamMode = StreamMode.paragraph
        var concurrency = 4
        var bufferSize = 512
        var quality = TranslationQuality.low
        var positionals: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--to":
                targetLanguage = try value(after: argument, in: arguments, index: &index)
            case "--from":
                sourceLanguage = try value(after: argument, in: arguments, index: &index)
            case "-s", "--stream":
                streamMode = .paragraph
                index += 1
            case "-j", "--concurrency":
                let concurrencyValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedConcurrency = Int(concurrencyValue), parsedConcurrency > 0 else {
                    throw CLIParseError.invalidValue(argument, concurrencyValue)
                }
                concurrency = parsedConcurrency
            case "-b", "--buffer-size":
                let bufferSizeValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedBufferSize = Int(bufferSizeValue), parsedBufferSize > 0 else {
                    throw CLIParseError.invalidValue(argument, bufferSizeValue)
                }
                bufferSize = parsedBufferSize
            case "-q", "--quality":
                let qualityValue = try value(after: argument, in: arguments, index: &index)
                guard let parsedQuality = TranslationQuality(rawValue: qualityValue.lowercased()) else {
                    throw CLIParseError.invalidValue(argument, qualityValue)
                }
                quality = parsedQuality
            default:
                if argument.hasPrefix("--") {
                    throw CLIParseError.unknownOption(argument)
                }
                positionals.append(argument)
                index += 1
            }
        }

        guard let targetLanguage else {
            throw CLIParseError.missingRequiredTo
        }

        guard positionals.count <= 1 else {
            throw CLIParseError.tooManyPositionalArguments
        }

        return CLIOptions(
            targetLanguage: targetLanguage,
            sourceLanguage: sourceLanguage,
            positionalText: positionals.first,
            streamMode: streamMode,
            concurrency: concurrency,
            bufferSize: bufferSize,
            quality: quality
        )
    }

    private func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIParseError.missingValue(option)
        }
        let value = arguments[valueIndex]
        guard !value.hasPrefix("-") else {
            throw CLIParseError.missingValue(option)
        }
        index += 2
        return value
    }
}

public let trnVersion = "0.2.0"
public let versionOutput = "trn \(trnVersion)\n"

public let usage = """
usage: trn --to <language> [--from <language>] [-q|--quality <high|low>] [-s|--stream] [-j|--concurrency <count>] [-b|--buffer-size <characters>] [text]

  trn --list-languages [--to <language>] [-q|--quality <high|low>]

Language listings are JSON. With --to, status describes each source -> target pair.

examples:
  trn --list-languages --to en --quality high
  trn --to en "こんにちは"
  trn --to en --quality high "こんにちは"
  trn --to en --quality low "こんにちは"
  echo "こんにちは" | trn --to english
  cat notes.txt | trn --to en --concurrency 4 --buffer-size 512
  trn --from ja --to en "こんにちは"
"""

public let helpOutput = "\(versionOutput)\n\(usage)"
