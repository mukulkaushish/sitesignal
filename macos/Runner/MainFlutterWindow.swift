import Cocoa
import FlutterMacOS
import ServiceManagement

class MainFlutterWindow: NSWindow {
  private var desktopChannel: FlutterMethodChannel?
  private var launchAtStartupChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "dev.sitesignal.app/desktop",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadgeCount":
        guard let count = call.arguments as? Int else {
          result(
            FlutterError(
              code: "invalid_badge_count",
              message: "Badge count must be an integer.",
              details: nil))
          return
        }
        NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
        result(nil)
      case "playSystemNotificationSound":
        NSSound.beep()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    desktopChannel = channel

    let startupChannel = FlutterMethodChannel(
      name: "launch_at_startup",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    startupChannel.setMethodCallHandler { call, result in
      guard #available(macOS 13.0, *) else {
        result(
          FlutterError(
            code: "launch_at_startup_unsupported",
            message: "Launch at login requires macOS 13 or later.",
            details: nil))
        return
      }

      let service = SMAppService.mainApp
      switch call.method {
      case "launchAtStartupIsEnabled":
        result(service.status == .enabled)
      case "launchAtStartupSetEnabled":
        guard
          let arguments = call.arguments as? [String: Any],
          let enabled = arguments["setEnabledValue"] as? Bool
        else {
          result(
            FlutterError(
              code: "invalid_startup_value",
              message: "The launch-at-login value must be a boolean.",
              details: nil))
          return
        }
        do {
          if enabled {
            if service.status != .enabled {
              try service.register()
            }
          } else if service.status != .notRegistered {
            try service.unregister()
          }
          result(nil)
        } catch {
          result(
            FlutterError(
              code: "launch_at_startup_failed",
              message: error.localizedDescription,
              details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    launchAtStartupChannel = startupChannel

    super.awakeFromNib()
  }
}
