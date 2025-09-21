import Cocoa
import Foundation

/// 音频电平表视图
class LevelMeterView: NSView {
    private var level: Float = 0.0
    // bars 从左到右表示时间序列（最左=最旧，最右=最新）
    private var bars: [Float] = Array(repeating: 0.0, count: 100)
    
    private enum Style {
        case recording
        case playback
    }
    
    private var style: Style = .recording
    private var sensitivityMultiplier: Float = 1.6
    private var compressionExponent: Float = 0.45 // 越小越跳
    private var smoothUpWeight: Float = 0.6      // 上行平滑
    private var smoothDownWeight: Float = 0.8    // 下行减少平滑，回落更快
    // 噪声门（视图侧）
    private let noiseGateThreshold: Float = 0.02
    private let noiseGateReleaseMs: Double = 200
    private let nearSilenceFloor: Float = 0.003
    private var belowThresholdSince: CFAbsoluteTime?

    // 峰值保持与回落
    private var peakHoldLevel: Float = 0.0
    private var lastUpdateTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let peakHoldMs: Double = 800      // 保持时间
    private let peakDecayPerSec: Float = 1.2  // 超过保持期后每秒衰减幅度（线性）
    private var peakHoldSince: CFAbsoluteTime?
    
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
        
        // 使用Web版本的浅灰背景
        layer?.backgroundColor = NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0).cgColor // #f9f9f9
        layer?.cornerRadius = 5
        layer?.borderWidth = 0
    }
    
    /// 更新音频电平（记录模式：把最新值推入最右侧，并整体向左滚动）
    func updateLevel(_ newLevel: Float) {
        level = max(0, min(1, newLevel))
        appendLevelToBars()
        needsDisplay = true
    }
    
    private func appendLevelToBars() {
        // 非线性提升灵敏度，增强视觉动态
        // 噪声门：若持续低于阈值超过 releaseMs，则硬置为0
        let now = CFAbsoluteTimeGetCurrent()
        if level < noiseGateThreshold {
            if belowThresholdSince == nil { belowThresholdSince = now }
        } else {
            belowThresholdSince = nil
        }
        var effectiveLevel = level
        if let t0 = belowThresholdSince, (now - t0) * 1000.0 >= noiseGateReleaseMs {
            effectiveLevel = nearSilenceFloor
        }
        let boosted = pow(min(1.0, effectiveLevel * sensitivityMultiplier), compressionExponent)
        let last = bars.last ?? 0
        // 上行/下行分别平滑：下行更快回落
        let isFalling = boosted < last
        let upKeep = 1.0 - smoothUpWeight
        let downKeep = 1.0 - smoothDownWeight
        let smoothed: Float
        if isFalling {
            smoothed = last * downKeep + boosted * smoothDownWeight
        } else {
            smoothed = last * upKeep + boosted * smoothUpWeight
        }

        // 峰值保持/回落
        let now2 = CFAbsoluteTimeGetCurrent()
        let dt = Float(now2 - lastUpdateTime)
        lastUpdateTime = now2
        if smoothed > peakHoldLevel {
            peakHoldLevel = smoothed
            peakHoldSince = now2
        } else {
            if let t0 = peakHoldSince, (now2 - t0) * 1000.0 >= peakHoldMs {
                peakHoldLevel = max(0, peakHoldLevel - peakDecayPerSec * dt)
            }
        }
        // 速度×2：每次推进两格
        if !bars.isEmpty {
            for _ in 0..<2 {
                for i in 0..<(bars.count - 1) {
                    bars[i] = bars[i + 1]
                }
                bars[bars.count - 1] = smoothed
            }
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        // 清除背景
        context.clear(dirtyRect)
        
        // 绘制背景
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        NSColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0).setFill() // #f9f9f9
        backgroundPath.fill()
        
        // 绘制多段式声纹
        drawBars(in: dirtyRect)
    }
    
    private func drawBars(in rect: NSRect) {
        // 减少左右边距，给电平条更多水平空间
        let leftPadding: CGFloat = 16
        let rightPadding: CGFloat = 16
        let verticalPadding: CGFloat = 8  // 最小边距
        let insetRect = NSRect(x: rect.minX + leftPadding,
                               y: rect.minY + verticalPadding,
                               width: rect.width - leftPadding - rightPadding,
                               height: rect.height - verticalPadding * 2)

        // 计算电平条参数
        let totalBars = CGFloat(bars.count)
        let barWidth = max(2.0, floor(insetRect.width / (totalBars * 1.2)))  // 增加条宽
        let barSpacing: CGFloat = barWidth * 0.3  // 减少间距，让条更密集

        // 绘制背景网格线（可选）
        NSColor(calibratedWhite: 0.9, alpha: 0.5).setStroke()
        let gridPath = NSBezierPath()
        gridPath.lineWidth = 0.5
        
        // 水平网格线
        for i in 0...4 {
            let y = insetRect.minY + (insetRect.height / 4) * CGFloat(i)
            gridPath.move(to: NSPoint(x: insetRect.minX, y: y))
            gridPath.line(to: NSPoint(x: insetRect.maxX, y: y))
        }
        gridPath.stroke()

        // 绘制电平条 - 从底部到顶部
        for (index, barLevel) in bars.enumerated() {
            let x = insetRect.minX + CGFloat(index) * (barWidth + barSpacing)
            
            // 电平条从底部开始，高度根据音频电平决定
            let height = CGFloat(barLevel) * insetRect.height
            let barRect = NSRect(x: x, y: insetRect.minY, width: barWidth, height: height)

            // 根据电平高度使用渐变色
            if barLevel > 0.8 {
                // 高电平 - 红色
                NSColor.systemRed.setFill()
            } else if barLevel > 0.6 {
                // 中高电平 - 橙色
                NSColor.systemOrange.setFill()
            } else if barLevel > 0.3 {
                // 中电平 - 黄色
                NSColor.systemYellow.setFill()
            } else {
                // 低电平 - 绿色
                NSColor.systemGreen.setFill()
            }
            
            NSBezierPath(rect: barRect).fill()
        }

        // 峰值保持指示 - 在最右侧绘制一条细线
        if peakHoldLevel > 0 {
            let lastX = insetRect.minX + CGFloat(max(0, bars.count - 1)) * (barWidth + barSpacing)
            let peakHeight = CGFloat(peakHoldLevel) * insetRect.height
            let peakY = insetRect.minY + peakHeight
            
            NSColor.systemRed.setStroke()
            let peakPath = NSBezierPath()
            peakPath.lineWidth = 2.0
            peakPath.move(to: NSPoint(x: lastX - 2, y: peakY))
            peakPath.line(to: NSPoint(x: lastX + barWidth + 2, y: peakY))
            peakPath.stroke()
        }
    }
    
    /// 重置电平表
    func reset() {
        level = 0.0
        bars = Array(repeating: 0.0, count: 100)
        needsDisplay = true
    }
    
    // MARK: - Style Controls
    enum SensitivityPreset { case stable, normal, sensitive }
    func setSensitivityPreset(_ preset: SensitivityPreset) {
        switch preset {
        case .stable:
            sensitivityMultiplier = 1.2
            compressionExponent = 0.55
            smoothUpWeight = 0.55
            smoothDownWeight = 0.7
        case .normal:
            sensitivityMultiplier = 1.6
            compressionExponent = 0.45
            smoothUpWeight = 0.6
            smoothDownWeight = 0.8
        case .sensitive:
            sensitivityMultiplier = 1.9
            compressionExponent = 0.4
            smoothUpWeight = 0.65
            smoothDownWeight = 0.85
        }
    }
    
    /// 开始动画
    func startAnimation() {
        // 可以在这里添加更复杂的动画逻辑
    }
    
    /// 停止动画
    func stopAnimation() {
        reset()
    }
}
