import Cocoa
import Foundation

/// 应用程序委托
class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    private var window: NSWindow!
    private var mainViewController: MainViewController!
    private let logger = Logger.shared
    
    // MARK: - Application Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("应用程序启动完成")
        
        // 设置应用策略
        NSApp.setActivationPolicy(.regular)

        // 设置应用 Dock 图标（从 Resources 加载 assets/AudioRecordLogo.png）
        if let iconURL = Bundle.main.url(forResource: "AudioRecordLogo", withExtension: "png") {
            if let iconImage = NSImage(contentsOf: iconURL) {
                NSApp.applicationIconImage = iconImage
                logger.info("应用图标已设置: AudioRecordLogo.png")
            } else {
                logger.warning("无法加载应用图标图像数据")
            }
        } else {
            logger.warning("未找到应用图标资源 AudioRecordLogo.png")
        }
        
        // 创建主窗口
        createMainWindow()
        
        // 立即显示窗口
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        logger.info("窗口立即显示 - 可见: \(window.isVisible)")
        
        logger.info("应用程序设置完成")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        logger.info("应用程序即将退出")
        
        // 清理资源
        cleanup()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        logger.info("最后一个窗口已关闭，应用程序应该退出")
        return true
    }
    
    // MARK: - Window Management
    private func createMainWindow() {
        let windowSize = NSMakeRect(0, 0, 764, 496)
        
        window = NSWindow(
            contentRect: windowSize,
            styleMask: [.titled, .closable, .miniaturizable], // 临时移除resizable
            backing: .buffered,
            defer: false
        )
        
        // 设置窗口属性
        window.title = "音频录制工具"
        window.isRestorable = false
        // 移除自动保存名称，强制使用新尺寸
        // window.setFrameAutosaveName("MainWindow")
        
        // 强制设置窗口尺寸 - 使用更直接的方法
        let newFrame = NSMakeRect(0, 0, 764, 496)
        window.setFrame(newFrame, display: true, animate: false)
        
        // 确保窗口尺寸被应用
        DispatchQueue.main.async {
            self.window.setFrame(newFrame, display: true, animate: false)
            self.window.center()
        }
        
        // 设置最小尺寸
        window.minSize = NSSize(width: 600, height: 400)
        
        // 确保窗口可以显示
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        
        // 创建主视图控制器
        mainViewController = MainViewController()
        window.contentViewController = mainViewController
        
        logger.info("主窗口已创建，大小: \(windowSize)")
        logger.info("窗口是否可见: \(window.isVisible)")
        logger.info("窗口层级: \(window.level.rawValue)")
    }
    
    // MARK: - Cleanup
    @MainActor
    private func cleanup() {
        // 停止所有音频操作
        if let audioController = mainViewController?.audioRecorderController {
            audioController.stopRecording()
            audioController.stopPlayback()
        }
        
        // 清理临时文件
        FileManagerUtils.shared.cleanupTempFiles()
        
        logger.info("应用程序清理完成")
    }
}
