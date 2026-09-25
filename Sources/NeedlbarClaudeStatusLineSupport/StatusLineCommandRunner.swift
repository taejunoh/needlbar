import Darwin
import Foundation

public enum StatusLineCommandRunner {
    /// Claude Code does not promise a shell for `statusLine.command`. Use its
    /// exported SHELL when executable so shell-specific syntax keeps working;
    /// an absent or unusable SHELL falls back to macOS's POSIX shell.
    public static func shellURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["SHELL"], path.hasPrefix("/"), access(path, X_OK) == 0 {
            var info = stat()
            if stat(path, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) {
                return URL(fileURLWithPath: path)
            }
        }
        return URL(fileURLWithPath: "/bin/sh")
    }

    @discardableResult
    public static func run(
        originalCommand: String?,
        generation: UUID,
        input: FileHandle,
        output: FileHandle,
        error: FileHandle,
        store: StatusLinePrivateStore,
        now: () -> Date,
        shell: URL = shellURL()
    ) -> Int32 {
        let command = originalCommand
        let process: Process?
        let pipe: Pipe?
        if let command {
            let child = Process()
            child.executableURL = shell
            child.arguments = ["-c", command]
            child.standardOutput = output
            child.standardError = error
            let childInput = Pipe()
            child.standardInput = childInput
            do {
                try child.run()
            } catch {
                return 127
            }
            // EPIPE must be an ordinary passthrough outcome, never terminate
            // the wrapper before the child exit status is returned.
            _ = fcntl(childInput.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            process = child
            pipe = childInput
        } else {
            process = nil
            pipe = nil
        }

        let signalForwarder = process.map(SignalForwarder.init)
        defer { signalForwarder?.stop() }
        var parsingCopy = Data()
        var exceededLimit = false
        var inputFailed = false
        while true {
            let chunk: Data
            do {
                guard let readChunk = try input.read(upToCount: 16 * 1024), !readChunk.isEmpty else { break }
                chunk = readChunk
            } catch {
                inputFailed = true
                break
            }

            if !exceededLimit {
                if parsingCopy.count + chunk.count <= StatusLineQuotaParser.maximumInputBytes {
                    parsingCopy.append(chunk)
                } else {
                    exceededLimit = true
                    parsingCopy.removeAll(keepingCapacity: false)
                }
            }

            if let pipe {
                let descriptor = pipe.fileHandleForWriting.fileDescriptor
                chunk.withUnsafeBytes { bytes in
                    var offset = 0
                    while offset < bytes.count {
                        let written = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                        if written > 0 { offset += written; continue }
                        if written < 0 && errno == EINTR { continue }
                        // A child that closes stdin early still owns its exit
                        // status and output. Continue draining our own stdin.
                        break
                    }
                }
            }
        }
        try? pipe?.fileHandleForWriting.close()

        if let process { process.waitUntilExit() }
        let exitCode: Int32
        if let process {
            if process.terminationReason == .uncaughtSignal {
                exitCode = 128 + process.terminationStatus
            } else {
                exitCode = process.terminationStatus
            }
        } else {
            do { try output.write(contentsOf: Data("Needlbar\n".utf8)); exitCode = 0 }
            catch { exitCode = 1 }
        }

        if !inputFailed && !exceededLimit,
           let record = StatusLineQuotaParser.parse(parsingCopy, generation: generation, receivedAt: now()),
           record.fiveHour != nil || record.sevenDay != nil {
            _ = try? store.publish(record)
        }
        return exitCode
    }
}

private final class SignalForwarder: @unchecked Sendable {
    private let process: Process
    private var sources: [any DispatchSourceSignal] = []
    private var previous: [(Int32, sig_t?)] = []

    init(_ process: Process) {
        self.process = process
        for number in [SIGINT, SIGTERM, SIGHUP] {
            previous.append((number, signal(number, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak process] in
                if let process, process.isRunning { _ = kill(process.processIdentifier, number) }
            }
            source.resume()
            sources.append(source)
        }
    }

    func stop() {
        for source in sources { source.cancel() }
        sources.removeAll()
        for (number, handler) in previous { signal(number, handler) }
        previous.removeAll()
    }
}
