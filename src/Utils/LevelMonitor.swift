import Foundation
import AVFoundation

/// 音频电平监控器
/// 提供统一的电平监控功能，支持录制和播放场景
class LevelMonitor {
    
    // MARK: - Properties
    private var timer: Timer?
    private var isMonitoring = false
    
    // 回调
    var onLevelUpdate: ((Float) -> Void)?
    
    // 监控配置
    private let updateInterval: TimeInterval = 0.1 // 100ms更新一次
    private let logger = Logger.shared
    
    // MARK: - Public Methods
    
    /// 开始监控
    /// - Parameter source: 监控源类型
    func startMonitoring(source: MonitoringSource) {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        
        switch source {
        case .recording(_):
            // 录制时的电平监控现在由AudioRecorderController直接提供
            // 这里不需要定时器，因为电平数据会通过tap回调实时提供
            logger.info("录制电平监控已启动（由AudioRecorderController提供真实数据）")
        case .playback(_):
            // 播放时的电平监控现在也由AudioRecorderController直接提供
            // 这里不需要定时器，因为电平数据会通过AVAudioEngine的tap回调实时提供
            logger.info("播放电平监控已启动（由AudioRecorderController提供真实数据）")
        case .simulated:
            // 对于系统音频录制，电平数据由SystemAudioStreamOutput直接提供
            // 这里不需要启动定时器，因为电平会通过onLevel回调实时更新
            logger.info("系统音频电平监控已启动（由SystemAudioStreamOutput提供真实数据）")
        }
    }
    
    /// 停止监控
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        isMonitoring = false
        timer?.invalidate()
        timer = nil
        onLevelUpdate?(0.0)
    }
    
    /// 重置监控器
    func reset() {
        stopMonitoring()
    }
    
    /// 手动更新电平（用于系统音频录制）
    func updateLevel(_ level: Float) {
        onLevelUpdate?(level)
    }
    
    // MARK: - Private Methods
    
    private func startRecordingLevelMonitoring(engine: AVAudioEngine) {
        // 录制时的电平监控现在由AudioRecorderController直接提供
        // 这里不需要定时器，因为电平数据会通过tap回调实时提供
        logger.info("录制电平监控已启动（由AudioRecorderController提供真实数据）")
    }
    
    private func startPlaybackLevelMonitoring(player: AVAudioPlayer) {
        // 播放时的电平监控现在由AudioRecorderController提供真实数据
        // 这里不需要定时器，因为电平数据会通过AVAudioEngine的tap回调实时提供
        logger.info("播放电平监控已启动（由AudioRecorderController提供真实数据）")
    }
    
    private func startSimulatedLevelMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.isMonitoring else { return }
            
            // 模拟随机电平（用于测试）
            let level = Float.random(in: 0.1...0.9)
            self.onLevelUpdate?(level)
        }
    }
    
}

// MARK: - Monitoring Source
extension LevelMonitor {
    /// 监控源类型
    enum MonitoringSource {
        case recording(engine: AVAudioEngine)
        case playback(player: AVAudioPlayer)
        case simulated
    }
}
