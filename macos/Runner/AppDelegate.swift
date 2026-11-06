import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationWillTerminate(_ notification: Notification) {
    let cleanup = Process()
    cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    cleanup.arguments = ["-TERM", "-P", String(ProcessInfo.processInfo.processIdentifier)]
    try? cleanup.run()
    cleanup.waitUntilExit()
    super.applicationWillTerminate(notification)
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
