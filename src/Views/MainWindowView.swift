import Cocoa
import Foundation

/// 主窗口视图
class MainWindowView: NSView {
    
    // MARK: - UI Elements
    private let cardView = NSView()
    private let titleLabel = NSTextField()
    private let modeContainer = NSView()
    private let modeLabel = NSTextField()
    private let modeSwitchButton = NSButton()
    private let timerLabel = NSTextField()
    private let levelMeterView = LevelMeterView()
    private let startButton = NSButton()
    private let stopButton = NSButton()
    private let playButton = NSButton()
    private let downloadButton = NSButton()
    private let formatLabel = NSTextField()
    private let formatPopup = NSPopUpButton()
    private let statusLabel = NSTextField()
    private let permissionButton = NSButton()
    
    // MARK: - Properties
    weak var delegate: MainWindowViewDelegate?
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupBackground()
        setupUI()
        setupConstraints()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupBackground()
        setupUI()
        setupConstraints()
    }
    
    private func setupBackground() {
        wantsLayer = true
        
        // 使用Web版本的浅灰背景
        layer?.backgroundColor = NSColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0).cgColor
    }
    
    // MARK: - UI Setup
    private func setupUI() {
        setupCardView()
        setupTitleLabel()
        setupModeContainer()
        setupTimerLabel()
        setupLevelMeterView()
        setupButtons()
        setupFormatControls()
        setupPermissionButton()
        setupStatusLabel()
    }
    
    private func setupCardView() {
        cardView.wantsLayer = true
        // 使用Web版本的白色卡片背景
        cardView.layer?.backgroundColor = NSColor.white.cgColor
        cardView.layer?.cornerRadius = 10
        cardView.layer?.borderWidth = 0 // 隐藏调试边框
        cardView.layer?.borderColor = NSColor.clear.cgColor
        
        // 使用Web版本的阴影效果
        cardView.layer?.shadowColor = NSColor.black.cgColor
        cardView.layer?.shadowOffset = NSSize(width: 0, height: 4)
        cardView.layer?.shadowRadius = 6
        cardView.layer?.shadowOpacity = 0.1
        cardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cardView)
    }
    
    private func setupTitleLabel() {
        titleLabel.stringValue = "" // 隐藏标题
        titleLabel.font = NSFont.systemFont(ofSize: 24, weight: .bold)
        // 使用Web版本的主色调
        titleLabel.textColor = NSColor(red: 0.17, green: 0.24, blue: 0.31, alpha: 1.0) // #2c3e50
        titleLabel.backgroundColor = NSColor.clear
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.isHidden = true // 完全隐藏标题
        cardView.addSubview(titleLabel)
    }
    
    private func setupModeContainer() {
        Logger.shared.info("正在设置模式容器...")
        modeContainer.translatesAutoresizingMaskIntoConstraints = false
        modeContainer.wantsLayer = true
        
        // 使用Web版本的模式指示器样式（添加调试边框）
        modeContainer.layer?.backgroundColor = NSColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1.0).cgColor // #ecf0f1
        modeContainer.layer?.cornerRadius = 8
        modeContainer.layer?.borderWidth = 0 // 隐藏调试边框
        modeContainer.layer?.borderColor = NSColor.clear.cgColor
        
        cardView.addSubview(modeContainer)
        
        // 模式标签 - 使用Web版本样式
        modeLabel.stringValue = "录制模式：麦克风"
        modeLabel.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        modeLabel.textColor = NSColor(red: 0.17, green: 0.24, blue: 0.31, alpha: 1.0) // #2c3e50
        modeLabel.backgroundColor = NSColor.clear
        modeLabel.isBordered = false
        modeLabel.isEditable = false
        modeLabel.alignment = .center
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeContainer.addSubview(modeLabel)
        
        // 切换按钮 - 使用Web版本的胶囊设计
        modeSwitchButton.title = "切换录制模式"
        modeSwitchButton.target = self
        modeSwitchButton.action = #selector(modeSwitchButtonClicked)
        modeSwitchButton.bezelStyle = .shadowlessSquare
        modeSwitchButton.isBordered = false
        modeSwitchButton.isEnabled = true
        modeSwitchButton.wantsLayer = true
        
        // 优化录制模式切换按钮颜色
        modeSwitchButton.layer?.backgroundColor = NSColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1.0).cgColor // #3498db 蓝色
        modeSwitchButton.layer?.cornerRadius = 14 // 完全圆形 (高度28/2)
        modeSwitchButton.layer?.borderWidth = 0 // 隐藏调试边框
        modeSwitchButton.layer?.borderColor = NSColor.clear.cgColor
        
        modeSwitchButton.attributedTitle = NSAttributedString(
            string: "切换录制模式",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .bold)
            ]
        )
        modeSwitchButton.translatesAutoresizingMaskIntoConstraints = false
        
        // 添加调试信息
        Logger.shared.info("模式切换按钮设置:")
        Logger.shared.info("目标对象: \(String(describing: modeSwitchButton.target))")
        Logger.shared.info("动作方法: \(String(describing: modeSwitchButton.action))")
        Logger.shared.info("是否启用: \(modeSwitchButton.isEnabled)")
        
        modeContainer.addSubview(modeSwitchButton)
        
        // 添加额外的点击测试
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(modeSwitchButtonClicked))
        modeSwitchButton.addGestureRecognizer(clickGesture)
        Logger.shared.info("已添加点击手势识别器到按钮")
    }
    
    private func setupTimerLabel() {
        timerLabel.stringValue = "00:00:00"
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 36, weight: .bold) // 恢复36pt字体，60px高度足够
        timerLabel.textColor = NSColor(red: 0.17, green: 0.24, blue: 0.31, alpha: 1.0) // #2c3e50
        timerLabel.backgroundColor = NSColor.clear
        timerLabel.isBordered = false
        timerLabel.isEditable = false
        timerLabel.alignment = .center
        timerLabel.wantsLayer = true // 启用layer以添加调试边框
        timerLabel.layer?.borderWidth = 0 // 隐藏调试边框
        timerLabel.layer?.borderColor = NSColor.clear.cgColor
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(timerLabel)
    }
    
    private func setupLevelMeterView() {
        levelMeterView.translatesAutoresizingMaskIntoConstraints = false
        levelMeterView.wantsLayer = true
        levelMeterView.layer?.borderWidth = 0 // 隐藏调试边框
        levelMeterView.layer?.borderColor = NSColor.clear.cgColor
        cardView.addSubview(levelMeterView)
    }
    
    private func setupButtons() {
        setupStartButton()
        setupStopButton()
        setupPlayButton()
        setupDownloadButton()
    }
    
    private func setupStartButton() {
        startButton.title = "开始录制麦克风"
        startButton.target = self
        startButton.action = #selector(startButtonClicked)
        startButton.bezelStyle = .shadowlessSquare
        startButton.isBordered = false
        startButton.wantsLayer = true
        
        // 使用Web版本的红色胶囊按钮
        startButton.layer?.backgroundColor = NSColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1.0).cgColor // #e74c3c
        startButton.layer?.cornerRadius = 20 // 完全圆形 (高度40/2)
        startButton.layer?.borderWidth = 0 // 隐藏调试边框
        startButton.layer?.borderColor = NSColor.clear.cgColor
        
        startButton.attributedTitle = NSAttributedString(
            string: "开始录制麦克风",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .bold)
            ]
        )
        startButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(startButton)
    }
    
    private func setupStopButton() {
        stopButton.title = "停止录音"
        stopButton.target = self
        stopButton.action = #selector(stopButtonClicked)
        stopButton.bezelStyle = .shadowlessSquare
        stopButton.isBordered = false
        stopButton.wantsLayer = true
        
        // 使用Web版本的蓝色胶囊按钮
        stopButton.layer?.backgroundColor = NSColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1.0).cgColor // #3498db
        stopButton.layer?.cornerRadius = 20 // 完全圆形 (高度40/2)
        stopButton.layer?.borderWidth = 0 // 隐藏调试边框
        stopButton.layer?.borderColor = NSColor.clear.cgColor
        
        stopButton.attributedTitle = NSAttributedString(
            string: "停止录音",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .bold)
            ]
        )
        stopButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(stopButton)
    }
    
    private func setupPlayButton() {
        playButton.title = "播放录音"
        playButton.target = self
        playButton.action = #selector(playButtonClicked)
        playButton.bezelStyle = .shadowlessSquare
        playButton.isBordered = false
        playButton.wantsLayer = true
        
        // 使用Web版本的橙色胶囊按钮
        playButton.layer?.backgroundColor = NSColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1.0).cgColor // #f39c12
        playButton.layer?.cornerRadius = 20 // 完全圆形 (高度40/2)
        playButton.layer?.borderWidth = 0 // 隐藏调试边框
        playButton.layer?.borderColor = NSColor.clear.cgColor
        
        playButton.attributedTitle = NSAttributedString(
            string: "播放录音",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .bold)
            ]
        )
        playButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(playButton)
    }
    
    private func setupDownloadButton() {
        downloadButton.title = "下载录音"
        downloadButton.target = self
        downloadButton.action = #selector(downloadButtonClicked)
        downloadButton.bezelStyle = .shadowlessSquare
        downloadButton.isBordered = false
        downloadButton.wantsLayer = true
        
        // 使用Web版本的绿色胶囊按钮
        downloadButton.layer?.backgroundColor = NSColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0).cgColor // #2ecc71
        downloadButton.layer?.cornerRadius = 20 // 完全圆形 (高度40/2)
        downloadButton.layer?.borderWidth = 0 // 隐藏调试边框
        downloadButton.layer?.borderColor = NSColor.clear.cgColor
        
        downloadButton.attributedTitle = NSAttributedString(
            string: "下载录音",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 14, weight: .bold)
            ]
        )
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(downloadButton)
    }
    
    private func setupFormatControls() {
        formatLabel.stringValue = "导出格式:"
        formatLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        formatLabel.textColor = NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
        formatLabel.backgroundColor = NSColor.clear
        formatLabel.isBordered = false
        formatLabel.isEditable = false
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(formatLabel)
        
        formatPopup.addItems(withTitles: ["M4A", "MP3", "WAV"])
        formatPopup.selectItem(at: 0)
        formatPopup.target = self
        formatPopup.action = #selector(formatPopupChanged)
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(formatPopup)
    }
    
    private func setupPermissionButton() {
        permissionButton.title = "权限设置"
        permissionButton.target = self
        permissionButton.action = #selector(permissionButtonClicked)
        permissionButton.bezelStyle = .shadowlessSquare
        permissionButton.isBordered = false
        permissionButton.wantsLayer = true
        
        // 使用灰色按钮样式
        permissionButton.layer?.backgroundColor = NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0).cgColor
        permissionButton.layer?.cornerRadius = 15
        permissionButton.layer?.borderWidth = 0
        
        permissionButton.attributedTitle = NSAttributedString(
            string: "权限设置",
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 12, weight: .medium)
            ]
        )
        permissionButton.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(permissionButton)
    }
    
    private func setupStatusLabel() {
        statusLabel.stringValue = "准备就绪"
        statusLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        statusLabel.backgroundColor = NSColor.clear
        statusLabel.isBordered = false
        statusLabel.isEditable = false
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(statusLabel)
    }
    
    // MARK: - Constraints
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // 卡片容器 - 设置窗口大小为764x496
            cardView.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardView.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardView.widthAnchor.constraint(equalToConstant: 764),
            cardView.heightAnchor.constraint(equalToConstant: 496),
        
            // 标题 - 隐藏状态，不设置约束
            
            // 模式容器 - 增加宽度确保内容完整显示
            modeContainer.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 20),
            modeContainer.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            modeContainer.widthAnchor.constraint(equalToConstant: 350),
            modeContainer.heightAnchor.constraint(equalToConstant: 70),
            
            // 模式标签
            modeLabel.topAnchor.constraint(equalTo: modeContainer.topAnchor, constant: 10),
            modeLabel.centerXAnchor.constraint(equalTo: modeContainer.centerXAnchor),
            
            // 切换按钮 - 使用Web版本的精确尺寸
            modeSwitchButton.topAnchor.constraint(equalTo: modeLabel.bottomAnchor, constant: 8),
            modeSwitchButton.centerXAnchor.constraint(equalTo: modeContainer.centerXAnchor),
            modeSwitchButton.widthAnchor.constraint(equalToConstant: 100),
            modeSwitchButton.heightAnchor.constraint(equalToConstant: 28),
            
            // 计时器 - 增加高度约束解决底部截断问题
            timerLabel.topAnchor.constraint(equalTo: modeContainer.bottomAnchor, constant: 20),
            timerLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            timerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: cardView.leadingAnchor, constant: 10),
            timerLabel.trailingAnchor.constraint(lessThanOrEqualTo: cardView.trailingAnchor, constant: -10),
            timerLabel.heightAnchor.constraint(equalToConstant: 50), // 减少高度让布局更紧凑
            
            // 电平表 - 使用Web版本的100px高度
            levelMeterView.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 20),
            levelMeterView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 20),
            levelMeterView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -20),
            levelMeterView.heightAnchor.constraint(equalToConstant: 100),
            
            // 按钮 - 使用更合理的布局方式，确保固定间距
            startButton.topAnchor.constraint(equalTo: levelMeterView.bottomAnchor, constant: 20),
            startButton.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 50),
            startButton.widthAnchor.constraint(equalToConstant: 150),
            startButton.heightAnchor.constraint(equalToConstant: 40),
            
            stopButton.topAnchor.constraint(equalTo: levelMeterView.bottomAnchor, constant: 20),
            stopButton.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 20),
            stopButton.widthAnchor.constraint(equalToConstant: 130),
            stopButton.heightAnchor.constraint(equalToConstant: 40),
            
            playButton.topAnchor.constraint(equalTo: levelMeterView.bottomAnchor, constant: 20),
            playButton.leadingAnchor.constraint(equalTo: stopButton.trailingAnchor, constant: 20),
            playButton.widthAnchor.constraint(equalToConstant: 130),
            playButton.heightAnchor.constraint(equalToConstant: 40),
            
            downloadButton.topAnchor.constraint(equalTo: levelMeterView.bottomAnchor, constant: 20),
            downloadButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 20),
            downloadButton.widthAnchor.constraint(equalToConstant: 130),
            downloadButton.heightAnchor.constraint(equalToConstant: 40),
            
            // 导出格式 - 减少间距让布局更紧凑
            formatLabel.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 30),
            formatLabel.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 40),
            
            formatPopup.centerYAnchor.constraint(equalTo: formatLabel.centerYAnchor),
            formatPopup.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 12),
            formatPopup.widthAnchor.constraint(equalToConstant: 100),
            formatPopup.heightAnchor.constraint(equalToConstant: 28),
            
            // 权限设置按钮
            permissionButton.centerYAnchor.constraint(equalTo: formatLabel.centerYAnchor),
            permissionButton.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -40),
            permissionButton.widthAnchor.constraint(equalToConstant: 80),
            permissionButton.heightAnchor.constraint(equalToConstant: 30),
            
            // 状态标签 - 减少间距让布局更紧凑
            statusLabel.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 15),
            statusLabel.centerXAnchor.constraint(equalTo: cardView.centerXAnchor),
            statusLabel.bottomAnchor.constraint(lessThanOrEqualTo: cardView.bottomAnchor, constant: -30)
        ])
    }
    
    // MARK: - Actions
    @objc func modeSwitchButtonClicked() {
        // 添加点击动画效果
        animateButtonClick(modeSwitchButton) {
            // 添加明显的视觉反馈
            self.modeSwitchButton.title = "🔄 切换中..."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.modeSwitchButton.title = "🔄 切换录制模式"
            }
        }
        
        Logger.shared.info("🎯 模式切换按钮被点击!")
        Logger.shared.info("按钮是否启用: \(modeSwitchButton.isEnabled)")
        Logger.shared.info("按钮目标对象: \(String(describing: modeSwitchButton.target))")
        Logger.shared.info("按钮动作方法: \(String(describing: modeSwitchButton.action))")
        Logger.shared.info("委托对象: \(String(describing: delegate))")
        
        if let delegate = delegate {
            Logger.shared.info("✅ 正在调用委托方法...")
            delegate.mainWindowViewDidSwitchMode(self)
        } else {
            Logger.shared.error("❌ 未设置委托对象!")
        }
    }
    
    private func animateButtonClick(_ button: NSButton, completion: @escaping () -> Void) {
        // 缩放动画
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.95
        scaleAnimation.duration = 0.1
        scaleAnimation.autoreverses = true
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion()
        }
        button.layer?.add(scaleAnimation, forKey: "scale")
        CATransaction.commit()
    }
    
    @objc private func startButtonClicked() {
        animateButtonClick(startButton) {
            self.delegate?.mainWindowViewDidStartRecording(self)
        }
    }
    
    @objc private func stopButtonClicked() {
        animateButtonClick(stopButton) {
            Logger.shared.info("🛑 停止按钮被点击!")
            Logger.shared.info("停止按钮是否启用: \(self.stopButton.isEnabled)")
            Logger.shared.info("委托对象: \(String(describing: self.delegate))")
            
            if let delegate = self.delegate {
                Logger.shared.info("✅ 正在调用停止录制委托方法...")
                delegate.mainWindowViewDidStopRecording(self)
            } else {
                Logger.shared.error("❌ 未设置委托对象!")
            }
        }
    }
    
    @objc private func playButtonClicked() {
        animateButtonClick(playButton) {
            self.delegate?.mainWindowViewDidPlayRecording(self)
        }
    }
    
    @objc private func downloadButtonClicked() {
        animateButtonClick(downloadButton) {
            self.delegate?.mainWindowViewDidDownloadRecording(self)
        }
    }
    
    @objc private func formatPopupChanged() {
        delegate?.mainWindowViewDidChangeFormat(self, format: formatPopup.selectedItem?.title ?? "M4A")
    }
    
    @objc private func permissionButtonClicked() {
        animateButtonClick(permissionButton) {
            self.delegate?.mainWindowViewDidOpenPermissions(self)
        }
    }
    
    // MARK: - Public Methods
    func debugButtonPosition() {
        Logger.shared.info("🔍 调试按钮位置信息:")
        Logger.shared.info("按钮frame: \(modeSwitchButton.frame)")
        Logger.shared.info("按钮bounds: \(modeSwitchButton.bounds)")
        Logger.shared.info("按钮superview: \(String(describing: modeSwitchButton.superview))")
        Logger.shared.info("按钮window: \(String(describing: modeSwitchButton.window))")
        Logger.shared.info("按钮isHidden: \(modeSwitchButton.isHidden)")
        Logger.shared.info("按钮alpha: \(modeSwitchButton.alphaValue)")
        Logger.shared.info("按钮isEnabled: \(modeSwitchButton.isEnabled)")
    }
    
    func updateTimer(_ timeString: String) {
        timerLabel.stringValue = timeString
    }
    
    func updateStatus(_ status: String) {
        statusLabel.stringValue = status
    }
    
    func updateLevel(_ level: Float) {
        levelMeterView.updateLevel(level)
    }
    
    func updateMode(_ mode: AudioUtils.RecordingMode) {
        modeLabel.stringValue = "录制模式: \(mode.displayName)"
        startButton.title = mode.buttonTitle
        startButton.attributedTitle = NSAttributedString(
            string: mode.buttonTitle,
            attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14, weight: .medium)]
        )
    }
    
    func updateRecordingState(_ state: RecordingState) {
        switch state {
        case .idle:
            startButton.isEnabled = true
            stopButton.isEnabled = false
            playButton.isEnabled = true
            downloadButton.isEnabled = true
            modeSwitchButton.isEnabled = true
            levelMeterView.reset()
        case .preparing:
            startButton.isEnabled = false
            stopButton.isEnabled = false
            playButton.isEnabled = false
            downloadButton.isEnabled = false
            modeSwitchButton.isEnabled = false
        case .recording:
            startButton.isEnabled = false
            stopButton.isEnabled = true
            playButton.isEnabled = false
            downloadButton.isEnabled = false
            modeSwitchButton.isEnabled = false
            levelMeterView.startAnimation()
        case .stopping:
            startButton.isEnabled = false
            stopButton.isEnabled = false
            playButton.isEnabled = false
            downloadButton.isEnabled = false
            modeSwitchButton.isEnabled = false
        case .playing:
            startButton.isEnabled = true
            stopButton.isEnabled = false
            playButton.isEnabled = false
            downloadButton.isEnabled = true
            modeSwitchButton.isEnabled = true
        case .error:
            startButton.isEnabled = true
            stopButton.isEnabled = false
            playButton.isEnabled = true
            downloadButton.isEnabled = true
            modeSwitchButton.isEnabled = true
            levelMeterView.reset()
        }
    }
}

// MARK: - Delegate Protocol
protocol MainWindowViewDelegate: AnyObject {
    func mainWindowViewDidSwitchMode(_ view: MainWindowView)
    func mainWindowViewDidStartRecording(_ view: MainWindowView)
    func mainWindowViewDidStopRecording(_ view: MainWindowView)
    func mainWindowViewDidPlayRecording(_ view: MainWindowView)
    func mainWindowViewDidDownloadRecording(_ view: MainWindowView)
    func mainWindowViewDidChangeFormat(_ view: MainWindowView, format: String)
    func mainWindowViewDidOpenPermissions(_ view: MainWindowView)
}
