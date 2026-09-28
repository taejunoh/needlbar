import Foundation
import Darwin
import Testing
@testable import NeedlbarClaudeStatusLineSupport

private func runnerFixture(originalCommand: ((URL) -> String?)? = nil) throws -> (URL, StatusLinePrivateStore, UUID) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("needlbar-runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let store = try StatusLinePrivateStore(rootURL: root)
    let generation = UUID()
    try store.prepare(metadata: StatusLineConnectionMetadata(generation: generation, originalStatusLineJSON: nil,
        originalCommand: originalCommand?(root), ownedStatusLineJSON: Data()))
    try store.activate(generation: generation)
    return (root, store, generation)
}

private func fileHandle(_ url: URL, data: Data = Data()) throws -> FileHandle {
    FileManager.default.createFile(atPath: url.path, contents: data)
    return try FileHandle(forUpdating: url)
}

@Test func runnerStreamsOversizedInputAndPreservesOutputErrorAndExit() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let capture = root.appendingPathComponent("capture")
    let stdout = root.appendingPathComponent("stdout")
    let stderr = root.appendingPathComponent("stderr")
    let input = root.appendingPathComponent("input")
    let bytes = Data(repeating: 0x51, count: 262_145)
    let inputHandle = try fileHandle(input, data: bytes)
    let outputHandle = try fileHandle(stdout)
    let errorHandle = try fileHandle(stderr)
    defer { try? inputHandle.close(); try? outputHandle.close(); try? errorHandle.close() }
    let command = "cat > '\(capture.path)'; printf ok; printf warning >&2; exit 17"
    let exitCode = StatusLineCommandRunner.run(originalCommand: command, generation: generation,
        input: inputHandle, output: outputHandle, error: errorHandle, store: store,
        now: { Date(timeIntervalSince1970: 1_790_000_000) })
    #expect(exitCode == 17)
    #expect(try Data(contentsOf: capture) == bytes)
    #expect(try Data(contentsOf: stdout) == Data("ok".utf8))
    #expect(try Data(contentsOf: stderr) == Data("warning".utf8))
    #expect(try store.read(expectedGeneration: generation) == nil)
}

@Test func runnerPublishesValidQuotaWithoutChangingOriginalOutput() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"), data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1790323200}}}"#.utf8))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "printf original", generation: generation,
        input: input, output: output, error: error, store: store,
        now: { Date(timeIntervalSince1970: 1_790_000_000) })
    #expect(exitCode == 0)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("original".utf8))
    #expect(try store.read(expectedGeneration: generation)?.fiveHour?.usedPercent == 25)
}

@Test func runnerPreservesInheritedWorkingDirectoryAndEnvironment() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "pwd; printf '%s' \"$USER\"", generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init)
    let text = try String(contentsOf: root.appendingPathComponent("out"), encoding: .utf8)
    #expect(exitCode == 0)
    #expect(text == "\(FileManager.default.currentDirectoryPath)\n\(ProcessInfo.processInfo.environment["USER"] ?? "")")
}

@Test func runnerDoesNotPublishAfterDisconnectDuringBlockedChild() throws {
    let (root, store, generation) = try runnerFixture()
    var workerFinished = false
    defer {
        // The runner and shell still own these paths/handles after a hard
        // timeout, so preserve them instead of racing asynchronous cleanup.
        if workerFinished { try? FileManager.default.removeItem(at: root) }
    }
    let gate = root.appendingPathComponent("gate")
    let input = try fileHandle(root.appendingPathComponent("input"), data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":25}}}"#.utf8))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer {
        if workerFinished {
            try? input.close()
            try? output.close()
            try? error.close()
        }
    }
    let started = root.appendingPathComponent("started")
    let completed = DispatchSemaphore(value: 0)
    Thread {
        _ = StatusLineCommandRunner.run(originalCommand: "touch '\(started.path)'; while [ ! -e '\(gate.path)' ]; do sleep 0.02; done; printf done", generation: generation,
            input: input, output: output, error: error, store: store, now: Date.init)
        completed.signal()
    }.start()
    let deadline = Date().addingTimeInterval(5)
    while !FileManager.default.fileExists(atPath: started.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    let childStarted = FileManager.default.fileExists(atPath: started.path)
    let disconnected = (try? store.deactivate(generation: generation)) != nil
    FileManager.default.createFile(atPath: gate.path, contents: Data())
    workerFinished = completed.wait(timeout: .now() + 5) == .success
    #expect(childStarted, "runner child must start within the bounded startup interval")
    #expect(disconnected, "store must deactivate while the child is blocked")
    #expect(workerFinished, "runner and child must finish before fixture cleanup")
    guard workerFinished else { return }
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("done".utf8))
    #expect(try store.read(expectedGeneration: generation) == nil)
}

@Test func runnerUsesChosenShellForShellSpecificExistingCommand() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "[[ abc =~ ^a ]] && print -r -- zsh-ok", generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init,
        shell: URL(fileURLWithPath: "/bin/zsh"))
    #expect(exitCode == 0)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("zsh-ok\n".utf8))
    #expect(StatusLineCommandRunner.shellURL(environment: ["SHELL": "/definitely/missing"]).path == "/bin/sh")
}

@Test func runnerPreservesChildExitWhenChildClosesStdinEarly() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"), data: Data(repeating: 0x51, count: 1024 * 1024))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "printf early; exit 9", generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init)
    #expect(exitCode == 9)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("early".utf8))
}

@Test func runnerDoesNotChangeChildResultWhenCacheIsUnsafe() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let quota = root.appendingPathComponent("quota.json")
    FileManager.default.createFile(atPath: quota.path, contents: Data("guard".utf8))
    chmod(quota.path, 0o644)
    let input = try fileHandle(root.appendingPathComponent("input"), data: Data(#"{"rate_limits":{"five_hour":{"used_percentage":25}}}"#.utf8))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "printf safe; exit 17", generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init)
    #expect(exitCode == 17)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("safe".utf8))
    #expect(try Data(contentsOf: quota) == Data("guard".utf8))
}

@Test func runnerKeepsAnExistingEmptyCommandEmpty() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "", generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init)
    #expect(exitCode == 0)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")).isEmpty)
}

@Test func runnerSkipsMalformedQuotaWithoutAlteringExistingCommand() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"), data: Data("not-json".utf8))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: "printf original", generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init)
    #expect(exitCode == 0)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("original".utf8))
    #expect(try store.read(expectedGeneration: generation) == nil)
}

@Test func runnerProvidesMinimalLineWhenNoOriginalCommandExists() throws {
    let (root, store, generation) = try runnerFixture()
    defer { try? FileManager.default.removeItem(at: root) }
    let input = try fileHandle(root.appendingPathComponent("input"))
    let output = try fileHandle(root.appendingPathComponent("out"))
    let error = try fileHandle(root.appendingPathComponent("err"))
    defer { try? input.close(); try? output.close(); try? error.close() }
    let exitCode = StatusLineCommandRunner.run(originalCommand: nil, generation: generation,
        input: input, output: output, error: error, store: store, now: Date.init)
    #expect(exitCode == 0)
    #expect(try Data(contentsOf: root.appendingPathComponent("out")) == Data("Needlbar\n".utf8))
}

private func builtStatusLineHelper() throws -> URL {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    for relative in [".build/out/Products/Debug/NeedlbarClaudeStatusLine",
                     ".build/arm64-apple-macosx/debug/NeedlbarClaudeStatusLine"] {
        let candidate = root.appendingPathComponent(relative)
        if access(candidate.path, X_OK) == 0 { return candidate }
    }
    throw CocoaError(.fileNoSuchFile)
}

private func waitForPath(_ path: String, timeout: TimeInterval = 3) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !FileManager.default.fileExists(atPath: path) && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.01)
    }
    return FileManager.default.fileExists(atPath: path)
}

private func waitForExit(_ process: Process, timeout: TimeInterval = 3) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    if !process.isRunning { process.waitUntilExit(); return true }
    return false
}

@Test func helperSIGTERMInterruptsOpenStdinAndReapsOriginalCommand() throws {
    let (root, _, generation) = try runnerFixture(originalCommand: { root in
        "echo $$ > '\(root.appendingPathComponent("child-pid").path)'; exec /bin/cat"
    })
    defer { try? FileManager.default.removeItem(at: root) }
    let childPID = root.appendingPathComponent("child-pid")
    let helper = Process()
    helper.executableURL = try builtStatusLineHelper()
    helper.arguments = [generation.uuidString]
    helper.environment = ProcessInfo.processInfo.environment.merging(["NEEDLBAR_STATUSLINE_TEST_ROOT": root.path]) { _, new in new }
    let input = Pipe()
    helper.standardInput = input
    helper.standardOutput = FileHandle.nullDevice
    helper.standardError = FileHandle.nullDevice
    try helper.run()
    defer {
        if helper.isRunning { kill(helper.processIdentifier, SIGKILL); try? input.fileHandleForWriting.close(); helper.waitUntilExit() }
        if let text = try? String(contentsOf: childPID, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) { kill(pid, SIGKILL) }
    }
    #expect(waitForPath(childPID.path))
    let child = Int32((try String(contentsOf: childPID, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines))!
    kill(helper.processIdentifier, SIGTERM)
    #expect(waitForExit(helper, timeout: 2), "helper must stop while parent still holds stdin open")
    #expect(helper.terminationStatus == 143)
    let deadline = Date().addingTimeInterval(2)
    while kill(child, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    #expect(kill(child, 0) != 0)
}

@Test func helperSIGTERMInterruptsBlockedWriteAndDescendant() throws {
    let (root, _, generation) = try runnerFixture(originalCommand: { root in
        "sleep 30 & echo $! > '\(root.appendingPathComponent("descendant-pid").path)'; wait"
    })
    defer { try? FileManager.default.removeItem(at: root) }
    let descendantPID = root.appendingPathComponent("descendant-pid")
    let input = root.appendingPathComponent("large-input")
    try Data(repeating: 0x51, count: 2 * 1024 * 1024).write(to: input)
    let helper = Process()
    helper.executableURL = try builtStatusLineHelper()
    helper.arguments = [generation.uuidString]
    helper.environment = ProcessInfo.processInfo.environment.merging(["NEEDLBAR_STATUSLINE_TEST_ROOT": root.path]) { _, new in new }
    helper.standardInput = try FileHandle(forReadingFrom: input)
    helper.standardOutput = FileHandle.nullDevice
    helper.standardError = FileHandle.nullDevice
    try helper.run()
    defer {
        if helper.isRunning { kill(helper.processIdentifier, SIGKILL); helper.waitUntilExit() }
        if let text = try? String(contentsOf: descendantPID, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) { kill(pid, SIGKILL) }
    }
    #expect(waitForPath(descendantPID.path))
    let child = Int32((try String(contentsOf: descendantPID, encoding: .utf8)).trimmingCharacters(in: .whitespacesAndNewlines))!
    Thread.sleep(forTimeInterval: 0.1)
    kill(helper.processIdentifier, SIGTERM)
    #expect(waitForExit(helper, timeout: 2), "helper must stop while child refuses stdin")
    #expect(helper.terminationStatus == 143)
    let deadline = Date().addingTimeInterval(2)
    while kill(child, 0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    #expect(kill(child, 0) != 0)
}
