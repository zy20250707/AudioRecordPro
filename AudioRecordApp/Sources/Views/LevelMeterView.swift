import Cocoa
import Foundation

/// 音频电平表视图
class LevelMeterView: NSView {
    private var level: Float = 0.0
    // bars 从左到右表示时间序列（最左=最旧，最右=最新）
    private var bars: [Float] = Array(repeating: 0.0, count: 80)
    
    private enum Style {
        case recording
        case playback
    }
    
    private var style: Style = .recording
    private var sensitivityMultiplier: Float = 1.6
    private var compressionExponent: Float = 0.45 // 越小越跳
    // 不灵敏：上升慢、下降更慢
    private var smoothUpWeight: Float = 0.15     // 上行更慢（attack 慢）
    private var smoothDownWeight: Float = 0.05   // 下行很慢（release 慢）
    // 分贝映射参数（避免轻易顶满）
    private let meterMinDB: Float = -60.0        // -60dB 作为噪声地板
    private let meterGamma: Float = 1.5          // 固定刻度：更强压缩，高电平更难顶满
    private let meterHeadroom: Float = 0.80      // 固定刻度：顶部留更多余量
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
    // 采样稀疏：控制推进频率
    private var updateTick: Int = 0
    private let sampleInterval: Int = 5   // 每5次刷新推进一次，横向更稀疏
    // 平滑左移：子像素位移 + 触发整列推进
    private var xOffset: CGFloat = 0.0
    private var advanceWidth: CGFloat = 2.0   // 每列的推进宽度（barWidth+spacing），实时在 draw 里更新
    private let stepPerFrame: CGFloat = 0.5   // 每帧左移像素，数值越大越快
    // 视觉低通（默认仍关闭，如需更钝可将 visualAlpha 调小）
    private var visualPrevLevel: Float = 0.0
    private let visualAlpha: Float = 1.0         // 1.0:无低通，0.2~0.35 更钝
    // 毛刺参数：小概率短促上冲
    private let spikeProbability: Float = 0.12   // 12% 概率出现毛刺
    private let spikeAdd: Float = 0.06           // 毛刺幅度（加法）
    
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
        var isSilent = false
        if let t0 = belowThresholdSince, (now - t0) * 1000.0 >= noiseGateReleaseMs {
            // 静音门：静音达到释放时间后，视图电平强制为0
            effectiveLevel = 0
            isSilent = true
        }
        // 将线性电平映射到 dB，再归一化到 [0,1]，避免快速顶满
        let boosted: Float
        if isSilent {
            boosted = 0
        } else {
            let linear = max(nearSilenceFloor, min(1.0, effectiveLevel * sensitivityMultiplier))
            let db = 20.0 * log10(linear)
            var normalized = (db - meterMinDB) / (0.0 - meterMinDB)
            normalized = max(0.0, min(1.0, normalized))
            boosted = min(pow(normalized, meterGamma), meterHeadroom)
        }
        let last = bars.last ?? 0
        // 上行/下行分别平滑：下行更快回落
        let isFalling = boosted < last
        let upKeep = 1.0 - smoothUpWeight
        let downKeep = 1.0 - smoothDownWeight
        let smoothed: Float
        if isSilent {
            smoothed = 0
        } else {
            if isFalling {
                smoothed = last * downKeep + boosted * smoothDownWeight
            } else {
                smoothed = last * upKeep + boosted * smoothUpWeight
            }
        }

        // 峰值保持/回落
        let now2 = CFAbsoluteTimeGetCurrent()
        let dt = Float(now2 - lastUpdateTime)
        lastUpdateTime = now2
        if isSilent {
            peakHoldLevel = 0
        } else if smoothed > peakHoldLevel {
            peakHoldLevel = smoothed
            peakHoldSince = now2
        } else {
            if let t0 = peakHoldSince, (now2 - t0) * 1000.0 >= peakHoldMs {
                peakHoldLevel = max(0, peakHoldLevel - peakDecayPerSec * dt)
            }
        }
        // 可选视觉低通
        let visualBase = isSilent ? 0 : (visualPrevLevel * (1.0 - visualAlpha) + smoothed * visualAlpha)
        visualPrevLevel = visualBase

        // 静音下不产生毛刺
        var display = visualBase
        if !isSilent {
            if Float.random(in: 0...1) < spikeProbability {
                display = min(meterHeadroom, visualBase + 0.08)  // 上冲更明显
            }
            // 顶端微扰动：更强的破顶
            if display > 0.75 {
                display = max(0, display - Float.random(in: 0...0.03))
            }
            if display > 0.90 {
                display = max(0, display - Float.random(in: 0...0.01))
            }
            // 轻微“顶部压扁”非线性
            if display > 0.8 {
                display = max(0, display - 0.02 * pow(display, 3))
            }
        }
        // 更新推进动画计数
        updateTick += 1
        // 子像素左移
        xOffset += stepPerFrame
        if xOffset >= advanceWidth {
            // 触发整列推进一格
            xOffset -= advanceWidth
            if !bars.isEmpty {
                for i in 0..<(bars.count - 1) { bars[i] = bars[i + 1] }
                // 按采样间隔更新最后一根高度，否则保持
                if updateTick % sampleInterval == 0 {
                    bars[bars.count - 1] = display
                }
            }
        } else {
            // 未推进时，只在采样间隔命中时更新最右条高度
            if updateTick % sampleInterval == 0, !bars.isEmpty {
                bars[bars.count - 1] = display
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

        // 计算电平条参数（控制间隔，并水平居中铺满可用空间）
        let totalBars = CGFloat(bars.count)
        let spacingFactor: CGFloat = 0.45  // 更大间距，条更粗更稀疏
        // 解方程: totalWidth = barWidth*count + (count-1)*(spacingFactor*barWidth) = insetWidth
        let denominator = totalBars + spacingFactor * max(0, totalBars - 1)
        let barWidth = max(1.0, floor(insetRect.width / max(1, denominator)))
        let barSpacing: CGFloat = barWidth * spacingFactor
        let usedWidth = barWidth * totalBars + barSpacing * max(0, totalBars - 1)
        let startX = insetRect.minX + max(0, (insetRect.width - usedWidth) / 2)
        advanceWidth = barWidth + barSpacing

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

        // 绘制电平条 - 单一黑色细竖线，围绕中线上下对称延展
        for (index, barLevel) in bars.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + barSpacing)
            
            // 条高度根据电平决定，围绕中线对称；使用可用高度（留白10%）避免顶满
            let innerPaddingRatio: CGFloat = 0.0
            let availableHeight = insetRect.height * (1.0 - innerPaddingRatio * 2.0)
            let halfHeight = (CGFloat(barLevel) * availableHeight) * 0.5
            let barRect = NSRect(
                x: x - xOffset,
                y: insetRect.midY - halfHeight,
                width: max(1.0, barWidth),
                height: max(1.0, halfHeight * 2)
            )

            // 单一黑色
            NSColor.black.setFill()
            NSBezierPath(rect: barRect).fill()
        }

        // 峰值保持指示 - 在最右侧绘制一条细线
        if peakHoldLevel > 0 {
            let lastX = insetRect.minX + CGFloat(max(0, bars.count - 1)) * (barWidth + barSpacing)
            let innerPaddingRatio: CGFloat = 0.0
            let availableHeight = insetRect.height * (1.0 - innerPaddingRatio * 2.0)
            let uiHeadroom: CGFloat = 0.9
            let peakHeight = CGFloat(peakHoldLevel) * availableHeight * 0.5 * uiHeadroom
            let peakY = insetRect.midY + peakHeight
            
            NSColor.black.setStroke()
            let peakPath = NSBezierPath()
            peakPath.lineWidth = 1.0
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
