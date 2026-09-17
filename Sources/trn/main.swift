import Foundation
import TranslateCore

let arguments = Array(CommandLine.arguments.dropFirst())
let command = try? CLIParser().parseCommand(arguments)
let readsInput: Bool
if case .translate = command {
    readsInput = true
} else {
    readsInput = false
}
let stdin = readsInput && FileHandle.standardInput.isReadableRegularOrPipe ? String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) : nil
let runner = CommandRunner(translator: AppleTranslator())
let result = await runner.run(arguments: arguments, stdin: stdin) { chunk in
    FileHandle.standardOutput.write(Data(chunk.utf8))
}

if !result.output.isEmpty {
    FileHandle.standardOutput.write(Data(result.output.utf8))
}

if !result.errorOutput.isEmpty {
    FileHandle.standardError.write(Data(result.errorOutput.utf8))
}

exit(result.exitCode)

private extension FileHandle {
    var isReadableRegularOrPipe: Bool {
        var statBuffer = stat()
        guard fstat(fileDescriptor, &statBuffer) == 0 else {
            return false
        }

        let mode = statBuffer.st_mode & S_IFMT
        return mode == S_IFREG || mode == S_IFIFO
    }
}
