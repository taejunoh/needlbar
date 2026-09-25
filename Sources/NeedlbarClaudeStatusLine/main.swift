import Foundation
import NeedlbarClaudeStatusLineSupport

guard CommandLine.arguments.count == 2,
      let generation = UUID(uuidString: CommandLine.arguments[1]),
      let store = try? StatusLinePrivateStore(),
      let metadata = try? store.metadata(for: generation)
else {
    exit(64)
}

let result = StatusLineCommandRunner.run(
    originalCommand: metadata.originalCommand,
    generation: generation,
    input: .standardInput,
    output: .standardOutput,
    error: .standardError,
    store: store,
    now: Date.init
)
exit(result)
