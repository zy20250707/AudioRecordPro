import Cocoa
import Foundation

/// 音频电平表视图
class LevelMeterView: NSView {
    private var level: Float = 0.0
    private var bars: [Float] = Array(repeating: 0.0, count: 50)
    private let animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in }
    
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
    
    /// 更新音频电平
    func updateLevel(_ newLevel: Float) {
        level = max(0, min(1, newLevel))
        
        // 更新多段式声纹
        updateBars()
        needsDisplay = true
    }
    
    private func updateBars() {
        // 只在有真实音频输入时更新电平条
        if level > 0 {
            // 基于真实音频电平更新多段式声纹效果
            for i in 0..<bars.count {
                let targetLevel = level * Float.random(in: 0.7...1.0)
                let decay = Float(0.8) // 衰减系数
                bars[i] = bars[i] * decay + targetLevel * (1 - decay)
            }
        } else {
            // 没有音频输入时，所有条都归零
            for i in 0..<bars.count {
                bars[i] = bars[i] * 0.9 // 快速衰减到0
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
        let insetRect = rect.insetBy(dx: 8, dy: 8)
        
        // 绘制Web风格的音频可视化条 - 高密度
        let barWidth = (insetRect.width / CGFloat(bars.count)) * 1.2
        let barSpacing: CGFloat = 0.3
        
        for (index, barLevel) in bars.enumerated() {
            let x = insetRect.minX + CGFloat(index) * (barWidth + barSpacing)
            let height = CGFloat(barLevel) * insetRect.height
            let y = insetRect.minY // 从底部开始，向上增长
            
            let barRect = NSRect(x: x, y: y, width: barWidth, height: height)
            
            // 使用Web版本的红色渐变色彩
            let redValue = min(255, Int(barLevel * 255) + 100)
            let color = NSColor(red: CGFloat(redValue) / 255.0, green: 50.0 / 255.0, blue: 50.0 / 255.0, alpha: 1.0)
            
            color.setFill()
            let barPath = NSBezierPath(rect: barRect)
            barPath.fill()
        }
    }
    
    /// 重置电平表
    func reset() {
        level = 0.0
        bars = Array(repeating: 0.0, count: 50)
        needsDisplay = true
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
