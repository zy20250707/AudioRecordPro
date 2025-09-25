import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

// MARK: - 全局 C 函数指针
/// 全局音频回调函数（C 函数指针）
@available(macOS 14.4, *)
func globalAudioCallback(
    inDevice: AudioDeviceID,
    inNow: UnsafePointer<AudioTimeStamp>,
    inInputData: UnsafePointer<AudioBufferList>,
    inInputTime: UnsafePointer<AudioTimeStamp>,
    inOutputData: UnsafeMutablePointer<AudioBufferList>,
    inOutputTime: UnsafePointer<AudioTimeStamp>,
    inClientData: UnsafeMutableRawPointer?
) -> OSStatus {
    // 通过 inClientData 获取 AudioCallbackHandler 实例
    guard let clientData = inClientData else {
        return noErr
    }
    
    let handler = Unmanaged<AudioCallbackHandler>.fromOpaque(clientData).takeUnretainedValue()
    
    // 处理音频数据
    let bufferList = inInputData.pointee
    let buffer = bufferList.mBuffers
    
    // 添加详细的调试信息（减少频率避免日志过多）
    // 使用全局变量来跟踪调用次数
    struct CallCounter {
        static var count = 0
        static var lastNonZeroDataSize = UInt32(0)
        static var nonZeroCount = 0
    }
    CallCounter.count += 1
    
    // 前几次回调都记录详细信息
    if CallCounter.count <= 5 {
        handler.logger.info("🎧 音频回调[\(CallCounter.count)]: device=\(inDevice), dataSize=\(buffer.mDataByteSize), channels=\(bufferList.mNumberBuffers)")
    }
    
    // 每100次回调记录一次统计信息
    if CallCounter.count % 100 == 1 && CallCounter.count > 5 {
        handler.logger.info("🎧 音频回调统计: 总调用次数=\(CallCounter.count), 非零数据次数=\(CallCounter.nonZeroCount)")
    }
    
    // 记录非零数据大小的情况
    if buffer.mDataByteSize > 0 {
        CallCounter.lastNonZeroDataSize = buffer.mDataByteSize
        CallCounter.nonZeroCount += 1
    }
    
    if CallCounter.count % 100 == 1 { // 每100次回调记录一次
        handler.logger.debug("🎧 音频回调[\(CallCounter.count)]: device=\(inDevice), dataSize=\(buffer.mDataByteSize), channels=\(bufferList.mNumberBuffers)")
        handler.logger.debug("📊 统计信息: 非零数据次数=\(CallCounter.nonZeroCount), 最后非零大小=\(CallCounter.lastNonZeroDataSize)")
    }
    
    // 如果连续1000次都是0数据，发出警告
    if CallCounter.count % 1000 == 0 && CallCounter.nonZeroCount == 0 {
        handler.logger.warning("⚠️ 警告: 已调用\(CallCounter.count)次音频回调，但从未收到有效数据！")
        handler.logger.warning("💡 建议: 检查Process Tap配置或QQ音乐是否真的在播放音频")
    }
    
    // 计算实际的帧数：使用正确的帧数计算
    // 对于32位浮点格式，每帧4字节，但需要考虑声道数
    let bytesPerSample = 4 // 32位浮点 = 4字节
    // 注意：bufferList.mNumberBuffers 是缓冲区数量，不是声道数
    // 对于交错格式，通常只有一个缓冲区包含所有声道数据
    let totalSamples = Int(buffer.mDataByteSize) / bytesPerSample
    // 从Process Tap获取的格式信息中获取声道数
    // 这里需要从实际的音频格式中获取，暂时使用默认值2
    let channels = 2 // TODO: 从实际的音频格式中获取声道数
    let frameCount = UInt32(totalSamples / channels)
    
    // 计算电平
    handler.calculateAndReportLevel(from: bufferList, frameCount: frameCount)
    
    // 写入音频数据
    handler.writeAudioData(from: bufferList, frameCount: frameCount)
    
    return noErr
}

// MARK: - AudioCallbackHandler
/// 音频回调处理器 - 负责处理音频数据流和文件写入
@available(macOS 14.4, *)
class AudioCallbackHandler {
    
    // MARK: - Properties
    let logger = Logger.shared
    private var audioFile: AVAudioFile?
    private var audioToolboxFileManager: AudioToolboxFileManager?
    private var onLevel: ((Float) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// 设置音频文件
    func setAudioFile(_ file: AVAudioFile) {
        self.audioFile = file
    }
    
    /// 设置 AudioToolbox 文件管理器
    func setAudioToolboxFileManager(_ manager: AudioToolboxFileManager) {
        self.audioToolboxFileManager = manager
        logger.info("🎵 AudioCallbackHandler: 设置 AudioToolbox 文件管理器")
    }
    
    /// 设置电平回调
    func setLevelCallback(_ callback: @escaping (Float) -> Void) {
        self.onLevel = callback
    }
    
    /// 创建音频回调函数
    func createAudioCallback() -> (AudioDeviceIOProc, UnsafeMutableRawPointer) {
        logger.info("🎧 AudioCallbackHandler: 创建音频回调函数...")
        // 创建 self 的不安全指针，用于传递给 C 回调函数
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        logger.info("✅ 音频回调函数创建成功，客户端数据指针: \(selfPointer)")
        return (globalAudioCallback, selfPointer)
    }
    
    /// 创建 PCM 缓冲区
    func makePCMBuffer(from bufferList: UnsafePointer<AudioBufferList>, frames: UInt32, asbd: AudioStreamBasicDescription) -> AVAudioPCMBuffer? {
        guard let audioFile = audioFile else { return nil }
        
        let format = audioFile.processingFormat
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            return nil
        }
        
        pcm.frameLength = AVAudioFrameCount(frames)
        
        let abl = bufferList.pointee
        let channels = Int(asbd.mChannelsPerFrame)
        let _ = Int(asbd.mBytesPerFrame) // 暂时未使用，但保留以备将来使用
        
        guard let src = abl.mBuffers.mData else { return nil }
        
        if let dst = pcm.floatChannelData {
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Float.self).advanced(by: c)
                let d = dst[c]
                for i in 0..<totalFrames {
                    d[i] = s.pointee
                    s = s.advanced(by: channels)
                }
            }
        } else if let dst = pcm.int16ChannelData {
            // 将32位浮点数据转换为16位整数数据
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Float.self).advanced(by: c)
                let d = dst[c]
                for i in 0..<totalFrames {
                    // 将浮点数转换为16位整数：-1.0 到 1.0 映射到 -32768 到 32767
                    let floatValue = s.pointee
                    let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                    d[i] = int16Value
                    s = s.advanced(by: channels)
                }
            }
        } else if let dst = pcm.int32ChannelData {
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Int32.self).advanced(by: c)
                let d = dst[c]
                for i in 0..<totalFrames {
                    d[i] = s.pointee
                    s = s.advanced(by: channels)
                }
            }
        }
        
        return pcm
    }
    
    // MARK: - Private Methods
    
    func calculateAndReportLevel(from bufferList: AudioBufferList, frameCount: UInt32) {
        guard let onLevel = onLevel else { 
            logger.debug("AudioCallbackHandler: 没有电平回调函数")
            return 
        }
        
        // 使用统一的工具类计算电平
        let (maxLevel, rmsLevel, normalizedLevel) = AudioUtils.calculateAudioLevel(from: bufferList, frameCount: frameCount)
        
        logger.debug("AudioCallbackHandler: 电平计算 - maxLevel: \(maxLevel), rmsLevel: \(rmsLevel), normalized: \(normalizedLevel)")
        
        DispatchQueue.main.async {
            onLevel(normalizedLevel)
        }
    }
    
     func writeAudioData(from bufferList: AudioBufferList, frameCount: UInt32) {
        guard frameCount > 0 else { 
            logger.debug("AudioCallbackHandler: 跳过写入 - frameCount: \(frameCount)")
            return 
        }
        
        // 优先使用 AudioToolbox 文件管理器
        if let audioToolboxManager = audioToolboxFileManager {
            do {
                try audioToolboxManager.writeAudioData(bufferList, frameCount: frameCount)
                logger.debug("AudioCallbackHandler: 使用 AudioToolbox 成功写入 \(frameCount) 帧音频数据")
                return
            } catch {
                logger.error("AudioCallbackHandler: AudioToolbox 写入失败: \(error.localizedDescription)")
                // 如果 AudioToolbox 失败，回退到 AVAudioFile
            }
        }
        
        // 回退到 AVAudioFile（保持向后兼容）
        guard let audioFile = audioFile else { 
            logger.debug("AudioCallbackHandler: 跳过写入 - 没有可用的文件管理器")
            return 
        }
        
        logger.debug("AudioCallbackHandler: 使用 AVAudioFile 准备写入 \(frameCount) 帧音频数据")
        
        // 创建PCM缓冲区，确保大小足够
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            logger.error("AudioCallbackHandler: 无法创建PCM缓冲区")
            return
        }
        
        // 调试：检查格式匹配
        logger.debug("AudioCallbackHandler: PCM缓冲区格式 - 声道数: \(audioFile.processingFormat.channelCount), 采样率: \(audioFile.processingFormat.sampleRate), 交错: \(audioFile.processingFormat.isInterleaved)")
        
        // 处理交错和非交错格式
        if bufferList.mNumberBuffers == 1 {
            // 交错格式：所有声道数据在一个buffer中
            let buffer = bufferList.mBuffers
            logger.debug("AudioCallbackHandler: 检查buffer数据 - mData: \(buffer.mData != nil), mDataByteSize: \(buffer.mDataByteSize)")
            guard buffer.mData != nil && buffer.mDataByteSize > 0 else { 
                logger.warning("AudioCallbackHandler: buffer数据无效，跳过写入")
                return 
            }
            
            // 计算输入数据的实际声道数
            let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let inputChannels = totalSamples / Int(frameCount)
            let outputChannels = Int(audioFile.processingFormat.channelCount)
            
            logger.debug("AudioCallbackHandler: 数据解析 - 总样本: \(totalSamples), 帧数: \(frameCount), 输入声道: \(inputChannels), 输出声道: \(outputChannels)")
            
            // 使用统一的工具类复制数据到PCM缓冲区
            let success = AudioUtils.copyAudioDataToPCMBuffer(
                from: bufferList,
                to: pcmBuffer,
                frameCount: frameCount,
                inputChannels: inputChannels,
                outputChannels: outputChannels
            )
            
            if !success {
                logger.warning("AudioCallbackHandler: 数据复制失败，跳过写入")
                return
            }
        } else {
            // 非交错格式：每个声道有独立的buffer
            logger.debug("AudioCallbackHandler: 处理非交错格式，buffer数量: \(bufferList.mNumberBuffers)")
            
            // 暂时跳过非交错格式的处理，记录警告
            logger.warning("AudioCallbackHandler: 非交错格式暂不支持，跳过数据写入")
            return
        }
        
        do {
            // 确保frameLength正确设置
            if pcmBuffer.frameLength == 0 {
                logger.warning("AudioCallbackHandler: PCM缓冲区帧数为0，跳过写入")
                return
            }
            
            // 调试：检查写入前的状态
            logger.debug("AudioCallbackHandler: 写入前检查 - frameLength: \(pcmBuffer.frameLength), frameCapacity: \(pcmBuffer.frameCapacity)")
            
            try audioFile.write(from: pcmBuffer)
            logger.debug("AudioCallbackHandler: 使用 AVAudioFile 成功写入 \(pcmBuffer.frameLength) 帧音频数据")
        } catch {
            logger.error("AudioCallbackHandler: AVAudioFile 写入失败: \(error.localizedDescription)")
        }
    }
}