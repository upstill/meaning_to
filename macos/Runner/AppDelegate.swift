import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Universal links (https://meaning-to.me/join?invite=...)
  override func application(
    _ application: NSApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
  ) -> Bool {
    guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
          let url = userActivity.webpageURL else { return false }
    sendUrlToFlutter(url)
    return true
  }

  private func sendUrlToFlutter(_ url: URL) {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else { return }
    let channel = FlutterMethodChannel(
      name: "me.meaningto/universal_links",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.invokeMethod("onLink", arguments: url.absoluteString)
  }
}
