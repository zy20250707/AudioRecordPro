import Cocoa
import Foundation

/// 音频波形显示视图 - 类似图2的波形效果
class WaveformView: NSView {
    
    // MARK: - Properties
    private var waveformData: [Float] = []
    private var maxDataPoints: Int = 200
    private var isRecording: Bool = false
    private let logger = Logger.shared
    
    // 显示样式
    private var barWidth: CGFloat = 2.0
    private var barSpacing: CGFloat = 1.0
    private var maxBarHeight: CGFloat = 40.0
    
    // 动画相关
    private var displayTimer: Timer?
    private var animationPhase: Float = 0.0
    
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
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.lightGray.cgColor
        
        // 初始化波形数据
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
    }
    
    // MARK: - Public Methods
    
    /// 更新音频电平数据
    func updateLevel(_ level: Float) {
        // 将新的电平数据添加到波形数组
        let normalizedLevel = max(0, min(1, level))
        
        // 模拟更丰富的波形数据（基于输入电平生成变化）
        let baseLevel = normalizedLevel
        let variation = sin(animationPhase) * 0.3 + 0.7
        let finalLevel = baseLevel * variation
        
        // 添加到波形数据
        waveformData.append(finalLevel)
        
        // 保持数组大小
        if waveformData.count > maxDataPoints {
            waveformData.removeFirst(waveformData.count - maxDataPoints)
        }
        
        animationPhase += 0.1
        
        // 触发重绘
        DispatchQueue.main.async {
            self.needsDisplay = true
        }
    }
    
    /// 开始录制
    func startRecording() {
        isRecording = true
        startAnimation()
    }
    
    /// 停止录制
    func stopRecording() {
        isRecording = false
        stopAnimation()
        // 清空波形数据
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
        needsDisplay = true
    }
    
    /// 重置波形
    func reset() {
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
        needsDisplay = true
    }
    
    // MARK: - Animation
    
    private func startAnimation() {
        stopAnimation()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }
    
    private func stopAnimation() {
        displayTimer?.invalidate()
        displayTimer = nil
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 清除背景
        context.clear(dirtyRect)
        
        // 绘制背景
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8)
        NSColor.white.setFill()
        backgroundPath.fill()
        
        // 绘制边框
        NSColor.lightGray.setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()
        
        // 绘制波形
        drawWaveform(in: dirtyRect)
    }
    
    private func drawWaveform(in rect: NSRect) {
        guard !waveformData.isEmpty else { return }
        
        let centerY = rect.midY
        let leftPadding: CGFloat = 20
        let rightPadding: CGFloat = 20
        let drawWidth = rect.width - leftPadding - rightPadding
        let drawHeight = min(maxBarHeight, rect.height - 20)
        
        // 计算每个数据点的位置
        let totalBars = CGFloat(waveformData.count)
        let availableWidth = drawWidth - (totalBars - 1) * barSpacing
        let calculatedBarWidth = min(barWidth, availableWidth / totalBars)
        let actualSpacing = totalBars > 1 ? (drawWidth - calculatedBarWidth * totalBars) / (totalBars - 1) : 0
        
        // 绘制波形条
        for (index, level) in waveformData.enumerated() {
            let x = leftPadding + CGFloat(index) * (calculatedBarWidth + actualSpacing)
            let barHeight = CGFloat(level) * drawHeight
            
            // 创建条形区域（从中心向上向下扩展）
            let barRect = NSRect(
                x: x,
                y: centerY - barHeight / 2,
                width: calculatedBarWidth,
                height: barHeight
            )
            
            // 根据电平高度选择颜色
            let color: NSColor
            if level > 0.8 {
                color = NSColor.systemRed
            } else if level > 0.6 {
                color = NSColor.systemOrange
            } else if level > 0.3 {
                color = NSColor.systemYellow
            } else if level > 0.1 {
                color = NSColor.systemGreen
            } else {
                color = NSColor.lightGray
            }
            
            // 绘制条形
            color.setFill()
            NSBezierPath(rect: barRect).fill()
        }
        
        // 绘制中心线
        NSColor.lightGray.setStroke()
        let centerLine = NSBezierPath()
        centerLine.lineWidth = 0.5
        centerLine.move(to: NSPoint(x: leftPadding, y: centerY))
        centerLine.line(to: NSPoint(x: rect.width - rightPadding, y: centerY))
        centerLine.stroke()
    }
    
    // MARK: - Deinit
    
    deinit {
        stopAnimation()
    }
}

// MARK: - WaveformView Extensions

extension WaveformView {
    
    /// 设置波形样式
    func setStyle(barWidth: CGFloat = 2.0, spacing: CGFloat = 1.0, maxHeight: CGFloat = 40.0) {
        self.barWidth = barWidth
        self.barSpacing = spacing
        self.maxBarHeight = maxHeight
    }
    
    /// 设置数据点数量
    func setMaxDataPoints(_ count: Int) {
        maxDataPoints = max(50, min(500, count))
        waveformData = Array(repeating: 0.0, count: maxDataPoints)
    }
}
