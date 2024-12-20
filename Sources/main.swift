import Foundation

actor LastStatus {
    var _status: Int32 = 0

    var status: Int32 { _status }

    func setStatus(status: Int32) {
        _status = status
    }
}

let lastStatus = LastStatus()

func printToStderr(_ msg: String) {
    let msg = msg.data(using: .utf8)!
    FileHandle.standardError.write(msg)
}

func prompt() {
    printToStderr("swift-sh> ")
}
func read() -> String? {
    prompt()
    let input = readLine()
    return input
}

func tokenize(_ line: String) -> [String] {
    var tokens: [String] = []
    var prevStr = ""

    for c in line {
        if c.isWhitespace || c == "|" || c == "<" || c == ">" {
            if prevStr != "" {
                tokens.append(prevStr)
                prevStr = ""
            }
        }
        if c.isWhitespace {
            // Do nothing
        } else if c == "|" || c == "<" || c == ">" {
            tokens.append(String(c))
        } else {
            prevStr.append(c)
        }
    }
    if prevStr != "" {
        tokens.append(prevStr)
        prevStr = ""
    }
    return tokens
}

enum ShellError: Error, Equatable {
    case syntaxError
    case commandNotFound(String)
    case fileError(String, String)
}

enum Element: Equatable {
    case command(String, [String])
    case pipe
    case redirectIn(String)
    case redirectOut(String)
}

func parseTokens(_ tokens: [String]) throws -> [Element] {
    if tokens.count == 0 {
        return []
    }

    var result: [Element] = []
    if tokens[0] == "|" || tokens[0] == "<" || tokens[0] == ">" {
        throw ShellError.syntaxError
    }

    var countRedirectIn = 0
    var countRedirectOut = 0
    var prevCommandStr = ""
    var prevCommandArgs: [String] = []
    var i = 0
    while i < tokens.count {
        let token = tokens[i]
        i += 1

        if token == "|" || token == "<" || token == ">" {
            if i >= tokens.count {
                throw ShellError.syntaxError
            }
            let nextToken = tokens[i]
            if nextToken == "|" || nextToken == "<" || nextToken == ">" {
                throw ShellError.syntaxError
            }

            result.append(Element.command(prevCommandStr, prevCommandArgs))
            prevCommandStr = ""
            prevCommandArgs = []
        }
        if token == "|" {
            result.append(.pipe)
            continue
        }
        if token == "<" {
            result.append(Element.redirectIn(tokens[i]))
            i += 1
            countRedirectIn += 1
            continue
        } else if token == ">" {
            result.append(Element.redirectOut(tokens[i]))
            i += 1
            countRedirectOut += 1
            continue
        }
        if prevCommandStr == "" {
            prevCommandStr = token
        } else {
            prevCommandArgs.append(token)
        }
    }

    if countRedirectIn >= 2 || countRedirectOut >= 2 {
        throw ShellError.syntaxError
    }
    if (countRedirectIn >= 1 || countRedirectOut >= 1) && prevCommandStr != "" {
        throw ShellError.syntaxError
    }

    if prevCommandStr != "" {
        result.append(.command(prevCommandStr, prevCommandArgs))
    }
    return result
}

func parse(_ line: String) throws -> [Element] {
    let tokens = tokenize(line)
    let elements = try parseTokens(tokens)
    return elements
}

func absolutePath(of command: String, in paths: [String]) throws -> String {
    if command.starts(with: "/") {
        return command
    }
    for path in paths {
        let fullPath = "\(path)/\(command)"
        if FileManager.default.isExecutableFile(atPath: fullPath) {
            return fullPath
        }
    }
    throw ShellError.commandNotFound(command)
}

func createProcess(_ command: String, _ args: [String]) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = args
    return process
}

func isBuiltInCommand(_ command: String) -> Bool {
    switch command {
    case "cd", "exit":
        return true
    default:
        return false
    }
}

func runCd(_ args: [String]) throws {
    let path: String
    if args.count >= 1 {
        path = args[0]
    } else {
        path = ProcessInfo.processInfo.environment["HOME"] ?? "."
    }
    if !FileManager.default.changeCurrentDirectoryPath(path) {
        throw ShellError.fileError(path, "Could not change directory to \(path)")
    }

    // if not setenv PATH, `cd /tmp; pwd` prints /private/tmp on macOS
    if setenv("PWD", path, 1) < 0 {
        throw ShellError.fileError(path, "Could not set PWD environment variable")
    }
}

func runExit(_ args: [String]) async {
    let status: Int32
    if args.count >= 1 {
        status = Int32(args[0]) ?? 0
    } else {
        status = await lastStatus.status
    }
    exit(status)
}

func runBuildInCommand(_ command: String, _ args: [String]) async throws {
    switch command {
    case "cd":
        try runCd(args)
    case "exit":
        await runExit(args)
    default:
        break  // Do nothing
    }
}

func run(_ elements: [Element]) async throws {
    let paths =
        (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)

    var commands: [Process] = []
    var currentCommand: Process = Process()
    var pipe: Pipe?

    var i = 0
    while i < elements.count {
        let element = elements[i]
        switch element {
        case .command(let command, let args):
            if isBuiltInCommand(command) {
                try await runBuildInCommand(command, args)
                return
            }
            let commandPath = try absolutePath(of: command, in: paths)
            currentCommand = createProcess(commandPath, args)
            if let p = pipe {
                currentCommand.standardInput = p
                pipe = nil
            }

            commands.append(currentCommand)
        case .pipe:
            pipe = Pipe()
            currentCommand.standardOutput = pipe
        case .redirectIn(let path):
            do {
                let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
                currentCommand.standardInput = fileHandle
            } catch {
                throw ShellError.fileError(path, error.localizedDescription)
            }
        case .redirectOut(let path):
            // cspell:disable-next
            let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
            let fileHandle = FileHandle(fileDescriptor: fd)
            currentCommand.standardOutput = fileHandle
        }
        i += 1
    }
    do {
        for command in commands {
            try command.run()
        }
        for command in commands {
            command.waitUntilExit()
        }
        let status = commands[commands.count - 1].terminationStatus
        await lastStatus.setStatus(status: status)
    } catch {
        printToStderr("Running Error: \(error)\n")
    }
}

func repl() async {
    while true {
        let input = read()
        if input == nil {
            break
        }
        let elements: [Element]
        do {
            elements = try parse(input!)
            if elements.count == 0 {
                continue
            }
            try await run(elements)
        } catch ShellError.syntaxError {
            printToStderr("Error: Syntax error\n")
        } catch ShellError.commandNotFound(let command) {
            printToStderr("Error: Command not found: \(command)\n")
        } catch ShellError.fileError(let path, let description) {
            printToStderr("Error: Could not open \(path): \(description)\n")
        } catch {
            printToStderr("Error: \(error)\n")
        }
    }
}

await repl()
