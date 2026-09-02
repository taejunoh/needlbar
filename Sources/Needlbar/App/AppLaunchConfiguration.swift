import Foundation

public enum AppLaunchConfiguration {
    case production
#if NEEDLBAR_ACCEPTANCE_DRIVER
    case acceptance(AcceptanceFixture)

    public static func acceptance(arguments: [String], inputRoot: URL) throws -> AppLaunchConfiguration {
        guard arguments.count == 3, arguments[1] == "--acceptance-fixture" else {
            throw AcceptanceFixtureFailure.fixturePathInvalid
        }
        let path = URL(fileURLWithPath: arguments[2], relativeTo: nil)
        let fixture = try AcceptanceFixtureParser.readAndParse(path: path, beneath: inputRoot)
        return .acceptance(fixture)
    }

    public static func processArguments(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> AppLaunchConfiguration {
        guard let root = environment["NEEDLBAR_ACCEPTANCE_INPUT_ROOT"], root.hasPrefix("/") else {
            throw AcceptanceFixtureFailure.fixturePathInvalid
        }
        return try acceptance(
            arguments: CommandLine.arguments,
            inputRoot: URL(fileURLWithPath: root, isDirectory: true)
        )
    }
#endif
}
