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
    
    // 计算实际的帧数：字节数除以每帧字节数
    let bytesPerFrame = Int(buffer.mDataByteSize) / Int(bufferList.mNumberBuffers) / 4 // 假设32位浮点
    let frameCount = UInt32(bytesPerFrame)
    
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
    private var onLevel: ((Float) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public Methods
    
    /// 设置音频文件
    func setAudioFile(_ file: AVAudioFile) {
        self.audioFile = file
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
        let bytesPerFrame = Int(asbd.mBytesPerFrame)
        
        guard let src = abl.mBuffers.mData else { return nil }
        
        if let dst = pcm.floatChannelData {
            let frameStride = Int(bytesPerFrame)
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Float.self).advanced(by: c)
                var d = dst[c]
                for i in 0..<totalFrames {
                    d[i] = s.pointee
                    s = s.advanced(by: channels)
                }
            }
        } else if let dst = pcm.int16ChannelData {
            // 将32位浮点数据转换为16位整数数据
            let frameStride = Int(bytesPerFrame)
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Float.self).advanced(by: c)
                var d = dst[c]
                for i in 0..<totalFrames {
                    // 将浮点数转换为16位整数：-1.0 到 1.0 映射到 -32768 到 32767
                    let floatValue = s.pointee
                    let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                    d[i] = int16Value
                    s = s.advanced(by: channels)
                }
            }
        } else if let dst = pcm.int32ChannelData {
            let frameStride = Int(bytesPerFrame)
            let totalFrames = Int(frames)
            for c in 0..<channels {
                var s = src.assumingMemoryBound(to: Int32.self).advanced(by: c)
                var d = dst[c]
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
        
        let buffer = bufferList.mBuffers
        guard let data = buffer.mData else { 
            logger.debug("AudioCallbackHandler: 音频数据为空")
            return 
        }
        
        let samples = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        
        logger.debug("AudioCallbackHandler: 计算电平 - frameCount: \(frameCount), sampleCount: \(sampleCount), dataSize: \(buffer.mDataByteSize)")
        
        var maxLevel: Float = 0.0
        var rmsLevel: Float = 0.0
        var sumSquares: Float = 0.0
        
        for i in 0..<sampleCount {
            let sample = abs(samples[i])
            if sample > maxLevel {
                maxLevel = sample
            }
            sumSquares += sample * sample
        }
        
        // 计算 RMS
        if sampleCount > 0 {
            rmsLevel = sqrt(sumSquares / Float(sampleCount))
        }
        
        // 转换为 dB
        let maxDB = maxLevel > 0 ? 20 * log10(maxLevel) : -96.0
        let rmsDB = rmsLevel > 0 ? 20 * log10(rmsLevel) : -96.0
        let normalizedLevel = max(0, min(1, (rmsDB + 96) / 96))
        
        logger.debug("AudioCallbackHandler: 电平计算 - maxLevel: \(maxLevel), rmsLevel: \(rmsLevel), maxDB: \(maxDB), rmsDB: \(rmsDB), normalized: \(normalizedLevel)")
        
        DispatchQueue.main.async {
            onLevel(normalizedLevel)
        }
    }
    
     func writeAudioData(from bufferList: AudioBufferList, frameCount: UInt32) {
        guard let audioFile = audioFile, frameCount > 0 else { 
            logger.debug("AudioCallbackHandler: 跳过写入 - audioFile: \(audioFile != nil), frameCount: \(frameCount)")
            return 
        }
        
        logger.debug("AudioCallbackHandler: 准备写入 \(frameCount) 帧音频数据")
        
        // 创建PCM缓冲区，确保大小足够
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
            logger.error("AudioCallbackHandler: 无法创建PCM缓冲区")
            return
        }
        
        // 复制音频数据到PCM缓冲区
        pcmBuffer.frameLength = frameCount
        
        // 复制bufferList中的数据到PCM缓冲区
        // 对于交错格式，所有声道数据在一个buffer中
        if bufferList.mNumberBuffers == 1 {
            let buffer = bufferList.mBuffers
            guard buffer.mData != nil && buffer.mDataByteSize > 0 else { return }
            
            if let dstChannelData = pcmBuffer.floatChannelData {
                let srcData = buffer.mData!.assumingMemoryBound(to: Float.self)
                let channels = Int(audioFile.processingFormat.channelCount)
                let frameCountInt = Int(frameCount)
                let channelDataSize = min(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels, frameCountInt)
                
                // 交错数据：左声道、右声道、左声道、右声道...
                for frame in 0..<channelDataSize {
                    for channel in 0..<channels {
                        let srcIndex = frame * channels + channel
                        if srcIndex < Int(buffer.mDataByteSize) / MemoryLayout<Float>.size {
                            dstChannelData[channel][frame] = srcData[srcIndex]
                        }
                    }
                }
            } else if let dstChannelData = pcmBuffer.int16ChannelData {
                let srcData = buffer.mData!.assumingMemoryBound(to: Float.self)
                let channels = Int(audioFile.processingFormat.channelCount)
                let frameCountInt = Int(frameCount)
                let channelDataSize = min(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels, frameCountInt)
                
                // 交错数据：左声道、右声道、左声道、右声道...
                for frame in 0..<channelDataSize {
                    for channel in 0..<channels {
                        let srcIndex = frame * channels + channel
                        if srcIndex < Int(buffer.mDataByteSize) / MemoryLayout<Float>.size {
                            // 将浮点数转换为16位整数
                            let floatValue = srcData[srcIndex]
                            let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                            dstChannelData[channel][frame] = int16Value
                        }
                    }
                }
            }
        }
        
        do {
            try audioFile.write(from: pcmBuffer)
            logger.debug("AudioCallbackHandler: 成功写入 \(frameCount) 帧音频数据")
        } catch {
            logger.error("AudioCallbackHandler: 写入音频文件失败: \(error.localizedDescription)")
        }
    }
}