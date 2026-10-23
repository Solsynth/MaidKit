import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// Height of the Flutter-drawn title bar, in points.
  ///
  /// The pane tab strip fills this row and doubles as the window title bar, so
  /// the traffic lights have to sit on the strip's center line rather than on
  /// AppKit's default title bar. The Dart side pushes the effective height —
  /// `kMaidKitTitleBarHeight` times the user's UI scale — because the whole
  /// window subtree is scaled.
  private var titleBarHeight: CGFloat = 40

  /// Re-centers the window buttons on every layout pass.
  ///
  /// AppKit re-lays-out the title bar on resize, on style changes and when
  /// leaving full screen, so the alignment is applied after each of those
  /// instead of once at launch.
  /// AppKit re-lays-out the title bar after resizes and style changes, so the
  /// lights are re-aligned at the end of every layout pass.
  override func layoutIfNeeded() {
    super.layoutIfNeeded()
    alignTrafficLights()
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let titleBarChannel = FlutterMethodChannel(
      name: "maidkit/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    titleBarChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if call.method == "setTitleBarHeight",
        let height = call.arguments as? NSNumber
      {
        self.titleBarHeight = CGFloat(truncating: height)
        self.alignTrafficLights()
      }
      result(nil)
    }

    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    if let appDelegate = NSApp.delegate as? AppDelegate {
      appDelegate.setupAppIconChannel(
        binaryMessenger: flutterViewController.engine.binaryMessenger
      )
    }

    super.awakeFromNib()
    alignTrafficLights()
  }

  /// Centers the standard window buttons in the merged title bar.
  ///
  /// The buttons are moved individually rather than through their container:
  /// that container is itself only as tall as AppKit's title bar and clips
  /// anything pushed below it, so shifting it moves the lights out of view.
  /// Each button keeps its own frame origin, so the alignment is derived from
  /// the title bar height on every call and never accumulates drift. Full
  /// screen hides the buttons and owns its own layout, so nothing moves there.
  private func alignTrafficLights() {
    guard !styleMask.contains(.fullScreen),
      let closeButton = standardWindowButton(.closeButton),
      let minimizeButton = standardWindowButton(.miniaturizeButton),
      let zoomButton = standardWindowButton(.zoomButton),
      let titleBar = closeButton.superview
    else { return }

    // The strip is taller than AppKit's title bar, so the lights move *down*
    // from where AppKit centers them: their center lands on the strip's center
    // line instead of the old bar's. The button's own height matters here —
    // frame origins are corners, not centers.
    let barHeight = titleBar.bounds.height
    let offset = (titleBarHeight - barHeight) / 2
    guard abs(offset) >= 0.5 else { return }

    for button in [closeButton, minimizeButton, zoomButton] {
      var frame = button.frame
      let centerFromTop = barHeight / 2 + offset
      let originY = titleBar.isFlipped
        ? titleBar.bounds.minY + centerFromTop - frame.height / 2
        : titleBar.bounds.maxY - centerFromTop - frame.height / 2
      guard abs(frame.origin.y - originY) >= 0.5 else { continue }
      frame.origin.y = originY
      button.frame = frame
    }
  }
}
