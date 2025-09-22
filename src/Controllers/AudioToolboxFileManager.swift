import Foundation
import AudioToolbox
import CoreAudio

/// 使用 AudioToolbox API 的音频文件管理器
/// 用于创建标准 WAV 文件，避免 AVAudioFile 的 FLLR 块问题
@available(macOS 14.4, *)
class AudioToolboxFileManager {
    
    // MARK: - Properties
    private let logger = Logger.shared
    private var audioFileID: AudioFileID?
    private var outputURL: URL?
    private var audioFormat: AudioStreamBasicDescription
    private var totalFramesWritten: UInt64 = 0
    
    // MARK: - Initialization
    
    init(audioFormat: AudioStreamBasicDescription) {
        self.audioFormat = audioFormat
        logger.info("🎵 AudioToolboxFileManager: 初始化，格式 - 采样率: \(audioFormat.mSampleRate), 声道数: \(audioFormat.mChannelsPerFrame), 位深: \(audioFormat.mBitsPerChannel)")
    }
    
    deinit {
        closeFile()
    }
    
    // MARK: - Public Methods
    
    /// 创建音频文件
    func createAudioFile(at url: URL) throws {
        logger.info("📁 AudioToolboxFileManager: 创建音频文件: \(url.path)")
        
        // 确保目录存在
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        
        // 删除已存在的文件
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
            logger.info("🗑️ 删除已存在的文件")
        }
        
        // 创建标准 WAV 格式的 AudioStreamBasicDescription
        var wavFormat = createStandardWAVFormat(from: audioFormat)
        
        // 使用 AudioFileCreateWithURL 创建文件
        let status = AudioFileCreateWithURL(
            url as CFURL,
            kAudioFileWAVEType,  // WAV 文件类型
            &wavFormat,
            AudioFileFlags(rawValue: 0),  // 不使用特殊标志
            &audioFileID
        )
        
        guard status == noErr, let fileID = audioFileID else {
            let error = NSError(domain: "AudioToolboxFileManager", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "创建音频文件失败: \(status)"
            ])
            logger.error("❌ AudioToolboxFileManager: 创建文件失败 - \(status)")
            throw error
        }
        
        self.outputURL = url
        logger.info("✅ AudioToolboxFileManager: 音频文件创建成功")
        logger.info("📊 文件格式: 采样率=\(wavFormat.mSampleRate), 声道数=\(wavFormat.mChannelsPerFrame), 位深=\(wavFormat.mBitsPerChannel)")
    }
    
    /// 写入音频数据
    func writeAudioData(_ bufferList: AudioBufferList, frameCount: UInt32) throws {
        guard let fileID = audioFileID else {
            logger.warning("⚠️ AudioToolboxFileManager: 文件未打开，跳过写入")
            return
        }
        
        guard frameCount > 0 else {
            logger.warning("⚠️ AudioToolboxFileManager: 帧数为0，跳过写入")
            return
        }
        
        // 转换32位浮点数据为16位整数数据
        let convertedData = try convertFloat32ToInt16(bufferList: bufferList, frameCount: frameCount)
        
        // 准备写入数据
        var inNumPackets = frameCount
        var ioNumBytes = UInt32(convertedData.count)
        
        // 使用 AudioFileWritePackets 写入数据
        let status = convertedData.withUnsafeBytes { bytes in
            AudioFileWritePackets(
                fileID,
                false,  // 不使用缓存
                ioNumBytes,
                nil,    // 包描述符（PCM 不需要）
                Int64(totalFramesWritten),  // 起始包
                &inNumPackets,
                bytes.baseAddress!
            )
        }
        
        guard status == noErr else {
            logger.error("❌ AudioToolboxFileManager: 写入数据失败 - \(status)")
            throw NSError(domain: "AudioToolboxFileManager", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "写入音频数据失败: \(status)"
            ])
        }
        
        totalFramesWritten += UInt64(inNumPackets)
        
        if totalFramesWritten % 1000 == 0 {  // 每1000帧记录一次
            logger.debug("📝 AudioToolboxFileManager: 已写入 \(totalFramesWritten) 帧")
        }
    }
    
    /// 关闭文件
    func closeFile() {
        if let fileID = audioFileID {
            AudioFileClose(fileID)
            audioFileID = nil
            logger.info("🔒 AudioToolboxFileManager: 文件已关闭，总共写入 \(totalFramesWritten) 帧")
        }
        outputURL = nil
        totalFramesWritten = 0
    }
    
    /// 获取文件信息
    func getFileInfo() -> (url: URL?, totalFrames: UInt64, duration: TimeInterval) {
        let duration = totalFramesWritten > 0 ? Double(totalFramesWritten) / audioFormat.mSampleRate : 0.0
        return (outputURL, totalFramesWritten, duration)
    }
    
    // MARK: - Private Methods
    
    /// 转换32位浮点数据为16位整数数据
    private func convertFloat32ToInt16(bufferList: AudioBufferList, frameCount: UInt32) throws -> Data {
        guard bufferList.mNumberBuffers == 1 else {
            throw NSError(domain: "AudioToolboxFileManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "不支持多缓冲区格式"
            ])
        }
        
        let buffer = bufferList.mBuffers
        guard let srcData = buffer.mData else {
            throw NSError(domain: "AudioToolboxFileManager", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "输入数据为空"
            ])
        }
        
        let frameCountInt = Int(frameCount)
        let channels = Int(audioFormat.mChannelsPerFrame)
        let totalSamples = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let inputChannels = totalSamples / frameCountInt
        
        logger.debug("🔄 数据转换: 输入声道=\(inputChannels), 输出声道=\(channels), 帧数=\(frameCountInt)")
        
        // 创建输出数据缓冲区
        let outputBytesPerFrame = channels * MemoryLayout<Int16>.size
        let outputDataSize = frameCountInt * outputBytesPerFrame
        var outputData = Data(count: outputDataSize)
        
        let srcFloatData = srcData.assumingMemoryBound(to: Float.self)
        
        outputData.withUnsafeMutableBytes { outputBytes in
            let dstInt16Data = outputBytes.bindMemory(to: Int16.self)
            
            if inputChannels == 1 && channels == 2 {
                // 单声道转立体声
                for frame in 0..<frameCountInt {
                    if frame < totalSamples {
                        let monoValue = srcFloatData[frame]
                        let int16Value = Int16(max(-1.0, min(1.0, monoValue)) * 32767.0)
                        dstInt16Data[frame * 2] = int16Value      // 左声道
                        dstInt16Data[frame * 2 + 1] = int16Value  // 右声道
                    }
                }
                logger.debug("🔄 单声道转立体声完成")
            } else if inputChannels == channels {
                // 声道数匹配：直接转换
                for frame in 0..<frameCountInt {
                    for channel in 0..<channels {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            let floatValue = srcFloatData[srcIndex]
                            let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                            dstInt16Data[frame * channels + channel] = int16Value
                        }
                    }
                }
                logger.debug("🔄 直接转换完成")
            } else {
                // 其他情况：尝试交错格式解析
                let channelDataSize = min(totalSamples / inputChannels, frameCountInt)
                for frame in 0..<channelDataSize {
                    for channel in 0..<min(channels, inputChannels) {
                        let srcIndex = frame * inputChannels + channel
                        if srcIndex < totalSamples {
                            let floatValue = srcFloatData[srcIndex]
                            let int16Value = Int16(max(-1.0, min(1.0, floatValue)) * 32767.0)
                            dstInt16Data[frame * channels + channel] = int16Value
                        }
                    }
                }
                logger.debug("🔄 交错格式解析完成")
            }
        }
        
        return outputData
    }
    
    /// 创建标准 WAV 格式
    private func createStandardWAVFormat(from inputFormat: AudioStreamBasicDescription) -> AudioStreamBasicDescription {
        var wavFormat = AudioStreamBasicDescription()
        
        // 基本格式信息
        wavFormat.mSampleRate = inputFormat.mSampleRate
        wavFormat.mChannelsPerFrame = inputFormat.mChannelsPerFrame
        wavFormat.mFormatID = kAudioFormatLinearPCM
        
        // 使用 16 位整数格式，确保最大兼容性
        wavFormat.mBitsPerChannel = 16
        wavFormat.mBytesPerFrame = wavFormat.mChannelsPerFrame * (wavFormat.mBitsPerChannel / 8)
        wavFormat.mFramesPerPacket = 1
        wavFormat.mBytesPerPacket = wavFormat.mBytesPerFrame * wavFormat.mFramesPerPacket
        
        // 格式标志：16位有符号整数，交错格式，打包格式，小端序
        wavFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | 
                                 kAudioFormatFlagIsPacked
        
        logger.info("🎵 创建标准WAV格式:")
        logger.info("   采样率: \(wavFormat.mSampleRate)")
        logger.info("   声道数: \(wavFormat.mChannelsPerFrame)")
        logger.info("   位深: \(wavFormat.mBitsPerChannel)")
        logger.info("   格式标志: \(wavFormat.mFormatFlags)")
        logger.info("   每帧字节数: \(wavFormat.mBytesPerFrame)")
        
        return wavFormat
    }
}
