import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  // 关闭窗口时隐藏到菜单栏，继续播放；用菜单栏图标或 ⌘Q 退出。
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  // 窗口隐藏后点程序坞图标，重新显示窗口。
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
