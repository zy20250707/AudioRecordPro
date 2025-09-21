import Cocoa
import Foundation

// MARK: - Delegate Protocol
protocol ControlPanelViewDelegate: AnyObject {
    func controlPanelViewDidStartRecording(_ view: ControlPanelView)
    func controlPanelViewDidStopRecording(_ view: ControlPanelView)
}

// MARK: - ControlPanelView
/// 控制面板视图 - 负责录音按钮和计时器显示
class ControlPanelView: NSView {
    
    // MARK: - UI Components
    private let timerLabel = NSTextField()
    private let buttonContainer = NSView()
    private let recordButton = NSButton()
    private let outerRingLayer = CAShapeLayer()
    private let innerSquareLayer = CALayer()
    
    // MARK: - Properties
    weak var delegate: ControlPanelViewDelegate?
    private var currentRecordingState: RecordingState = .idle
    private var buttonWidthConstraint: NSLayoutConstraint?
    private var buttonHeightConstraint: NSLayoutConstraint?
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // 背景色
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        
        setupTimer()
        setupButtonContainer()
        setupRecordButton()
        setupConstraints()
    }
    
    private func setupTimer() {
        timerLabel.stringValue = "00:00.00"
        timerLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold)
        timerLabel.textColor = NSColor.secondaryLabelColor
        timerLabel.backgroundColor = .clear
        timerLabel.isBordered = false
        timerLabel.isEditable = false
        timerLabel.alignment = .left
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timerLabel)
    }
    
    private func setupButtonContainer() {
        buttonContainer.wantsLayer = true
        buttonContainer.layer?.backgroundColor = NSColor.clear.cgColor
        buttonContainer.layer?.masksToBounds = false
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonContainer)
        
        // 外环（灰色描边）
        outerRingLayer.fillColor = NSColor.clear.cgColor
        outerRingLayer.strokeColor = NSColor(calibratedWhite: 0.0, alpha: 0.45).cgColor
        outerRingLayer.lineWidth = 8
        outerRingLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        buttonContainer.layer?.addSublayer(outerRingLayer)
    }
    
    private func setupRecordButton() {
        recordButton.title = ""
        recordButton.isBordered = false
        recordButton.wantsLayer = true
        recordButton.layer?.backgroundColor = NSColor.systemRed.cgColor
        recordButton.layer?.cornerRadius = 32
        recordButton.target = self
        recordButton.action = #selector(recordButtonClicked)
        recordButton.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.addSubview(recordButton)
        
        // 录制中视觉：内部白色方块（表示停止）
        if let layer = recordButton.layer {
            innerSquareLayer.backgroundColor = NSColor.white.cgColor
            innerSquareLayer.cornerRadius = 4
            innerSquareLayer.isHidden = true
            // 关闭隐式动画，避免约束动画时方块出现闪烁放大
            innerSquareLayer.actions = [
                "bounds": NSNull(),
                "position": NSNull(),
                "hidden": NSNull(),
                "contents": NSNull()
            ]
            // 初始尺寸，后续在 layout 调整为居中
            innerSquareLayer.frame = CGRect(x: (layer.bounds.width - 22) / 2,
                                           y: (layer.bounds.height - 22) / 2,
                                           width: 22,
                                           height: 22)
            layer.addSublayer(innerSquareLayer)
        }
    }
    
    private func setupConstraints() {
        let containerW = buttonContainer.widthAnchor.constraint(equalToConstant: 84)
        let containerH = buttonContainer.heightAnchor.constraint(equalToConstant: 84)
        let w = recordButton.widthAnchor.constraint(equalToConstant: 64)
        let h = recordButton.heightAnchor.constraint(equalToConstant: 64)
        
        buttonWidthConstraint = w
        buttonHeightConstraint = h
        
        NSLayoutConstraint.activate([
            buttonContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
            containerW,
            containerH,
            
            recordButton.centerXAnchor.constraint(equalTo: buttonContainer.centerXAnchor),
            recordButton.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor),
            w,
            h,
            
            timerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            timerLabel.centerYAnchor.constraint(equalTo: buttonContainer.centerYAnchor)
        ])
    }
    
    // MARK: - Actions
    @objc private func recordButtonClicked() {
        switch currentRecordingState {
        case .idle, .error:
            // 立即给出视觉反馈
            innerSquareLayer.isHidden = true
            recordButton.layer?.cornerRadius = 10
            delegate?.controlPanelViewDidStartRecording(self)
        case .preparing, .recording:
            innerSquareLayer.isHidden = true
            recordButton.layer?.cornerRadius = 10
            delegate?.controlPanelViewDidStopRecording(self)
        case .stopping, .playing:
            break
        }
    }
    
    // MARK: - Public Methods
    func updateTimer(_ timeString: String) {
        timerLabel.stringValue = timeString
    }
    
    func updateRecordingState(_ state: RecordingState) {
        currentRecordingState = state
        
        switch state {
        case .idle:
            recordButton.isEnabled = true
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            recordButton.layer?.cornerRadius = 32
        case .preparing:
            recordButton.isEnabled = false
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            recordButton.layer?.cornerRadius = 32
        case .recording:
            recordButton.isEnabled = true
            // 外形切换为方形停播样式
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = NSColor.systemGray.cgColor
            recordButton.layer?.cornerRadius = 10
        case .stopping:
            recordButton.isEnabled = false
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = NSColor.systemGray.cgColor
            recordButton.layer?.cornerRadius = 10
        case .playing:
            recordButton.isEnabled = false
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            recordButton.layer?.cornerRadius = 32
        case .error:
            recordButton.isEnabled = true
            innerSquareLayer.isHidden = true
            recordButton.layer?.backgroundColor = NSColor.systemRed.cgColor
            recordButton.layer?.cornerRadius = 32
        }
    }
    
    // MARK: - Layout
    override func layout() {
        super.layout()
        
        // 更新内方块的位置与外环路径
        if let layer = recordButton.layer {
            let size: CGFloat = 22
            innerSquareLayer.frame = CGRect(x: (layer.bounds.width - size) / 2,
                                           y: (layer.bounds.height - size) / 2,
                                           width: size,
                                           height: size)
        }
        
        // 外环路径：以容器中间为圆心，稍大于内部按钮，保留间距
        let bounds = buttonContainer.bounds
        if bounds.width > 0 && bounds.height > 0 {
            outerRingLayer.frame = bounds
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            let radius = min(bounds.width, bounds.height) / 2 - outerRingLayer.lineWidth / 2 - 1
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: center.x, y: center.y), radius: radius, startAngle: 0, endAngle: 360)
            // 构造 CGPath 兼容旧系统
            let cgPath = CGMutablePath()
            cgPath.addArc(center: CGPoint(x: center.x, y: center.y), radius: radius, startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: false)
            outerRingLayer.path = cgPath
        }
    }
}
