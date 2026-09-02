import AppKit
import NeedlbarApp

let application = NSApplication.shared
let launch: AppLaunchConfiguration
#if NEEDLBAR_ACCEPTANCE_DRIVER
do {
    launch = try AppLaunchConfiguration.processArguments()
} catch let failure as AcceptanceFixtureFailure {
    fputs("\(failure.description)\n", stderr)
    exit(64)
} catch {
    fputs("fixtureReadFailed\n", stderr)
    exit(64)
}
#else
launch = .production
#endif
let appDelegate = AppDelegate(launch: launch)
application.delegate = appDelegate
application.run()
