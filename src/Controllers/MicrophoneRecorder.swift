import Foundation
import AVFoundation

/// 麦克风录制器
@MainActor
class MicrophoneRecorder: BaseAudioRecorder {
    
    // MARK: - Properties
    private let engine = AVAudioEngine()
    private let recordMixer = AVAudioMixerNode()
    private var mixerFormat: AVAudioFormat?
    
    // MARK: - Initialization
    override init(mode: AudioUtils.RecordingMode) {
        super.init(mode: .microphone)
    }
    
    // MARK: - Recording Implementation
    override func startRecording() {
        guard !isRunning else {
            logger.warning("录制已在进行中")
            return
        }
        
        let url = fileManager.getRecordingFileURL(format: currentFormat.fileExtension)
        logger.info("开始录制，模式: \(recordingMode.rawValue), 格式: \(currentFormat.rawValue)")
        
        do {
            // Create audio file
            try createAudioFile(at: url, format: currentFormat)
            
            // Setup audio engine
            setupAudioEngine()
            
            // Install microphone recording tap
            installMicrophoneRecordingTap()
            
            // Start audio engine
            try startAudioEngine()
            
            // Start monitoring
            levelMonitor.startMonitoring(source: .recording(engine: engine))
            
            isRunning = true
            onStatus?("正在录制麦克风...")
            
        } catch {
            let errorMsg = "录制启动失败: \(error.localizedDescription)"
            onStatus?(errorMsg)
            logger.error("麦克风录制启动失败: \(error.localizedDescription)")
            
            // Check for permission issues
            if error.localizedDescription.contains("permission") || 
               error.localizedDescription.contains("权限") ||
               error.localizedDescription.contains("denied") {
                onStatus?("需要麦克风权限才能录制，请在系统设置中允许")
            }
        }
    }
    
    override func stopRecording() {
        // Stop microphone recording specific components
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            recordMixer.removeTap(onBus: 0)
            engine.stop()
            logger.info("麦克风录制引擎已停止")
        }
        
        // Call parent implementation
        super.stopRecording()
    }
    
    // MARK: - Private Methods
    private func setupAudioEngine() {
        engine.attach(recordMixer)
        
        let desiredSampleRate: Double = 48000
        let commonFormat = AVAudioCommonFormat.pcmFormatFloat32
        let mixerOutputFormat = AVAudioFormat(commonFormat: commonFormat, sampleRate: desiredSampleRate, channels: 2, interleaved: false)
        mixerFormat = mixerOutputFormat
        
        // Connect microphone input directly to mixer
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        logger.info("麦克风输入格式: \(inputFormat.settings)")
        logger.info("麦克风采样率: \(inputFormat.sampleRate), 声道数: \(inputFormat.channelCount)")
        
        // Use microphone's native format
        engine.connect(input, to: recordMixer, format: inputFormat)
        logger.info("已连接麦克风输入到混音器")
    }
    
    private func createAudioFile(at url: URL, format: AudioUtils.AudioFormat) throws {
        // Use microphone input format for recording
        let inputFormat = engine.inputNode.inputFormat(forBus: 0)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderBitRateKey: 128000
        ]
        logger.info("麦克风录制使用格式: \(audioSettings)")
        
        audioFile = try AVAudioFile(forWriting: url, settings: audioSettings)
        outputURL = url
        
        onStatus?("文件创建成功: \(url.lastPathComponent)")
        logger.info("麦克风录制文件创建成功: \(url.lastPathComponent)")
        logger.info("文件格式: \(audioFile?.processingFormat.settings ?? [:])")
    }
    
    private func installMicrophoneRecordingTap() {
        guard let mixerOutputFormat = mixerFormat else {
            logger.error("混音器格式未设置")
            return
        }
        
        recordMixer.installTap(onBus: 0, bufferSize: 4096, format: mixerOutputFormat) { [weak self] buffer, time in
            guard let self = self, let file = self.audioFile else { return }
            
            // Write to audio file
            do {
                try file.write(from: buffer)
            } catch {
                self.logger.error("写入麦克风音频失败: \(error.localizedDescription)")
            }
            
            // Calculate and update level
            let level = self.calculateRMSLevel(from: buffer)
            
            // Add debug info
            if level > 0.01 { // Only print when there's significant level
                self.logger.info("麦克风录制电平: \(String(format: "%.3f", level)), 帧数: \(buffer.frameLength)")
            }
            
            Task { @MainActor in
                self.onLevel?(level)
            }
        }
        
        logger.info("麦克风录制监听已安装")
    }
    
    private func startAudioEngine() throws {
        // Ensure no system output to avoid feedback
        engine.mainMixerNode.outputVolume = 0
        
        // Connect mixer to main mixer to drive rendering, but keep silent
        engine.connect(recordMixer, to: engine.mainMixerNode, format: mixerFormat)
        logger.info("已连接混音器到主混音器（麦克风模式）")
        
        try engine.start()
        logger.info("麦克风录制引擎启动成功")
    }
}
