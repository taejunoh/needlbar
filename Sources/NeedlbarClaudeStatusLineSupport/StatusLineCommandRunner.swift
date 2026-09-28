import Darwin
import Foundation

public enum StatusLineCommandRunner {
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
        originalCommand: String?, generation: UUID, input: FileHandle, output: FileHandle,
        error: FileHandle, store: StatusLinePrivateStore, now: () -> Date,
        shell: URL = shellURL()
    ) -> Int32 {
        let child: Child?
        if let originalCommand {
            guard let spawned = Child(command: originalCommand, shell: shell,
                                      output: output.fileDescriptor, error: error.fileDescriptor) else { return 127 }
            child = spawned
        } else {
            child = nil
        }
        let signals = SignalForwarder(childPID: child?.pid)
        defer { signals.stop() }
        var parsingCopy = Data()
        var exceededLimit = false
        var inputFailed = false
        var childInputOpen = child != nil
        var pending = Data()
        var offset = 0
        var inputComplete = false

        // Bounded poll plus nonblocking child writes make both an open stdin
        // and a child that refuses input interruptible by SIGTERM.
        while !inputComplete || offset < pending.count {
            if let number = signals.received { return cancel(child: child, signal: number) }
            let needWrite = childInputOpen && offset < pending.count
            var descriptor = pollfd(fd: needWrite ? child!.writeFD : input.fileDescriptor,
                                    events: Int16(needWrite ? POLLOUT : POLLIN), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 100)
            if ready == 0 { continue }
            if ready < 0 { if errno == EINTR { continue }; inputFailed = true; break }
            if needWrite {
                let written = pending.withUnsafeBytes { bytes in
                    Darwin.write(child!.writeFD, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                }
                if written > 0 {
                    offset += written
                    if offset == pending.count { pending.removeAll(keepingCapacity: true); offset = 0 }
                } else if written < 0 && errno != EINTR && errno != EAGAIN {
                    child?.closeInput(); childInputOpen = false
                    pending.removeAll(); offset = 0
                }
                continue
            }
            if inputComplete { break }
            var buffer = [UInt8](repeating: 0, count: 16 * 1024)
            let count = Darwin.read(input.fileDescriptor, &buffer, buffer.count)
            if count == 0 { inputComplete = true; break }
            if count < 0 { if errno == EINTR || errno == EAGAIN { continue }; inputFailed = true; break }
            if !exceededLimit {
                if parsingCopy.count + count <= StatusLineQuotaParser.maximumInputBytes {
                    parsingCopy.append(contentsOf: buffer[..<count])
                } else {
                    exceededLimit = true
                    parsingCopy.removeAll(keepingCapacity: false)
                }
            }
            if childInputOpen { pending = Data(buffer[..<count]); offset = 0 }
        }
        child?.closeInput()

        let exitCode: Int32
        if let child {
            while true {
                if let number = signals.received { return cancel(child: child, signal: number) }
                if let result = child.pollExit() { exitCode = result; break }
                Thread.sleep(forTimeInterval: 0.01)
            }
        } else {
            if let number = signals.received { return 128 + number }
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

    private static func cancel(child: Child?, signal: Int32) -> Int32 {
        child?.closeInput()
        child?.signalGroup(signal)
        let deadline = Date().addingTimeInterval(0.2)
        while let child, child.pollExit() == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        // The shell may exit first while a descendant remains in its group.
        child?.signalGroup(SIGKILL)
        _ = child?.pollExit()
        return 128 + signal
    }
}

private final class Child {
    let pid: pid_t
    let writeFD: Int32
    private var inputOpen = true
    private var exitCode: Int32?

    init?(command: String, shell: URL, output: Int32, error: Int32) {
        var descriptors = [Int32](repeating: -1, count: 2)
        guard pipe(&descriptors) == 0 else { return nil }
        defer { close(descriptors[0]) }
        var actions: posix_spawn_file_actions_t? = nil
        guard posix_spawn_file_actions_init(&actions) == 0 else { close(descriptors[1]); return nil }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawn_file_actions_adddup2(&actions, descriptors[0], STDIN_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, output, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, error, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors[1]) == 0,
              posix_spawn_file_actions_addclose(&actions, descriptors[0]) == 0 else {
            close(descriptors[1]); return nil
        }
        var attributes: posix_spawnattr_t? = nil
        guard posix_spawnattr_init(&attributes) == 0 else { close(descriptors[1]); return nil }
        defer { posix_spawnattr_destroy(&attributes) }
        var mask = sigset_t()
        var defaults = sigset_t()
        sigemptyset(&mask)
        sigemptyset(&defaults)
        for number in [SIGINT, SIGTERM, SIGHUP] { sigaddset(&defaults, number) }
        guard posix_spawnattr_setpgroup(&attributes, 0) == 0,
              posix_spawnattr_setsigmask(&attributes, &mask) == 0,
              posix_spawnattr_setsigdefault(&attributes, &defaults) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)) == 0 else {
            close(descriptors[1]); return nil
        }
        let shellPath: String = shell.path
        let args = [shellPath, "-c", command].map { strdup($0) }
        let environmentStrings: [String] = ProcessInfo.processInfo.environment.map { pair in
            pair.key + "=" + pair.value
        }
        let environment = environmentStrings.map { strdup($0) }
        defer { args.forEach { free($0) }; environment.forEach { free($0) } }
        guard args.allSatisfy({ $0 != nil }), environment.allSatisfy({ $0 != nil }) else {
            close(descriptors[1]); return nil
        }
        var argv = args + [nil]
        var envp = environment + [nil]
        var spawned: pid_t = 0
        let result = shellPath.withCString { path in
            posix_spawn(&spawned, path, &actions, &attributes, &argv, &envp)
        }
        if result != 0 { close(descriptors[1]); return nil }
        let flags = fcntl(descriptors[1], F_GETFL)
        _ = fcntl(descriptors[1], F_SETFL, flags | O_NONBLOCK)
        _ = fcntl(descriptors[1], F_SETNOSIGPIPE, 1)
        pid = spawned
        writeFD = descriptors[1]
    }

    func closeInput() {
        guard inputOpen else { return }
        inputOpen = false
        close(writeFD)
    }

    func signalGroup(_ number: Int32) { _ = kill(-pid, number) }

    func pollExit() -> Int32? {
        if let exitCode { return exitCode }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == 0 { return nil }
        if result == pid {
            exitCode = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        } else if errno == ECHILD { exitCode = 1 }
        return exitCode
    }
}

private final class SignalForwarder: @unchecked Sendable {
    private let lock = NSLock()
    private var caught: Int32?
    private var sources: [any DispatchSourceSignal] = []
    private var previous: [(Int32, sig_t?)] = []
    var received: Int32? { lock.lock(); defer { lock.unlock() }; return caught }

    init(childPID: pid_t?) {
        for number in [SIGINT, SIGTERM, SIGHUP] {
            previous.append((number, signal(number, SIG_IGN)))
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.lock.lock()
                if self.caught == nil { self.caught = number }
                self.lock.unlock()
                if let childPID { _ = kill(-childPID, number) }
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
