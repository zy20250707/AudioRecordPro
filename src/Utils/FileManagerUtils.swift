import Foundation

/// 文件管理工具类
class FileManagerUtils {
    static let shared = FileManagerUtils()
    
    private let fileManager = FileManager.default
    private let logger = Logger.shared
    
    private init() {}
    
    /// 获取录音文件保存目录
    func getRecordingsDirectory() -> URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsDir = documentsPath.appendingPathComponent("AudioRecordings")
        
        // 确保目录存在
        createDirectoryIfNeeded(at: recordingsDir)
        
        return recordingsDir
    }
    
    /// 创建目录（如果不存在）
    func createDirectoryIfNeeded(at url: URL) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            logger.debug("目录已创建/验证: \(url.path)")
        } catch {
            logger.error("创建目录失败 \(url.path): \(error.localizedDescription)")
        }
    }
    
    /// 生成录音文件名
    func generateRecordingFileName(format: String) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        return "record_\(timestamp).\(format.lowercased())"
    }
    
    /// 获取录音文件完整路径
    func getRecordingFileURL(format: String) -> URL {
        let directory = getRecordingsDirectory()
        let filename = generateRecordingFileName(format: format)
        return directory.appendingPathComponent(filename)
    }
    
    /// 检查文件是否存在
    func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    /// 获取文件大小
    func getFileSize(at url: URL) -> Int64? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            logger.error("获取文件大小失败 \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 格式化文件大小
    func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// 复制文件
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        // 确保目标目录存在
        createDirectoryIfNeeded(at: destinationURL.deletingLastPathComponent())
        
        // 如果目标文件已存在，先删除
        if fileExists(at: destinationURL) {
            try fileManager.removeItem(at: destinationURL)
        }
        
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        logger.info("文件已从 \(sourceURL.lastPathComponent) 复制到 \(destinationURL.lastPathComponent)")
    }
    
    /// 删除文件
    func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
        logger.info("文件已删除: \(url.lastPathComponent)")
    }
    
    /// 获取录音文件列表
    func getRecordingFiles() -> [URL] {
        let recordingsDir = getRecordingsDirectory()
        
        do {
            let files = try fileManager.contentsOfDirectory(at: recordingsDir, includingPropertiesForKeys: [.creationDateKey], options: [])
            return files.filter { url in
                let pathExtension = url.pathExtension.lowercased()
                return ["m4a", "mp3", "wav"].contains(pathExtension)
            }.sorted { url1, url2 in
                // 按创建时间降序排列
                let date1 = try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                let date2 = try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                return date1 ?? Date.distantPast > date2 ?? Date.distantPast
            }
        } catch {
            logger.error("获取录音文件失败: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 清理临时文件
    func cleanupTempFiles() {
        let tempDir = fileManager.temporaryDirectory
        
        do {
            let tempFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: [.creationDateKey], options: [])
            let oneHourAgo = Date().addingTimeInterval(-3600) // 1小时前
            
            for fileURL in tempFiles {
                if fileURL.path.contains("record_") {
                    if let creationDate = try fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < oneHourAgo {
                        try fileManager.removeItem(at: fileURL)
                        logger.info("已清理临时文件: \(fileURL.lastPathComponent)")
                    }
                }
            }
        } catch {
            logger.error("清理临时文件失败: \(error.localizedDescription)")
        }
    }
}
