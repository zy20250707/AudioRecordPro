import Foundation
import AppKit
import os.log

/// 日志级别枚举
enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case fatal = "FATAL"
    
    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .fatal:
            return .fault
        }
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .fatal: return "💥"
        }
    }
}

/// 日志工具类
class Logger {
    static let shared = Logger()
    
    private let osLog = OSLog(subsystem: "com.audiorecordmac", category: "AudioRecord")
    private let fileManager = FileManager.default
    private let logQueue = DispatchQueue(label: "com.audiorecordmac.logger", qos: .utility)
    
    private var logDirectory: URL {
        // 使用沙盒容器中的 Documents 目录
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("AudioRecordings/Logs")
    }
    
    private var logFileURL: URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        return logDirectory.appendingPathComponent("audiorecord_\(dateString).log")
    }
    
    private init() {
        // 尝试恢复之前保存的安全作用域书签
        restoreSecurityScopedBookmark()
        setupLogDirectory()
    }
    
    private func restoreSecurityScopedBookmark() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "documentsDirectoryBookmark") else {
            return
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("⚠️ 安全作用域书签已过期，需要重新授权")
                return
            }
            
            let success = url.startAccessingSecurityScopedResource()
            if success {
                print("✅ 安全作用域书签恢复成功")
            } else {
                print("❌ 安全作用域书签恢复失败")
            }
        } catch {
            print("❌ 恢复安全作用域书签失败: \(error.localizedDescription)")
        }
    }
    
    private func setupLogDirectory() {
        do {
            try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
            print("✅ 日志目录创建成功: \(logDirectory.path)")
        } catch {
            print("❌ 创建日志目录失败: \(error.localizedDescription)")
            print("   尝试的路径: \(logDirectory.path)")
        }
    }
    
    
    /// 记录日志
    func log(_ level: LogLevel, _ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = DateFormatter.logTimestamp.string(from: Date())
        let logMessage = "[\(timestamp)] \(level.emoji) [\(level.rawValue)] [\(fileName):\(line)] \(function): \(message)"
        
        // 控制台输出（同时写入统一日志与stdout，便于CLI调试）
        os_log("%{public}@", log: osLog, type: level.osLogType, logMessage)
        print(logMessage)
        
        // 文件输出
        logQueue.async { [weak self] in
            self?.writeToFile(logMessage)
        }
    }
    
    private func writeToFile(_ message: String) {
        let logEntry = message + "\n"
        
        if fileManager.fileExists(atPath: logFileURL.path) {
            // 追加到现有文件
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logEntry.data(using: .utf8) ?? Data())
                fileHandle.closeFile()
            }
        } else {
            // 创建新文件
            try? logEntry.write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    /// 获取日志文件路径
    func getLogFileURL() -> URL {
        return logFileURL
    }
    
    /// 获取日志目录路径
    func getLogDirectoryURL() -> URL {
        return logDirectory
    }
    
    /// 清理旧日志文件（保留最近7天）
    func cleanupOldLogs() {
        logQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let logFiles = try self.fileManager.contentsOfDirectory(at: self.logDirectory, includingPropertiesForKeys: [.creationDateKey])
                let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
                
                for fileURL in logFiles {
                    if let creationDate = try fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                       creationDate < sevenDaysAgo {
                        try self.fileManager.removeItem(at: fileURL)
                        self.log(.info, "Deleted old log file: \(fileURL.lastPathComponent)")
                    }
                }
            } catch {
                self.log(.error, "Failed to cleanup old logs: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 便捷方法
extension Logger {
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message, file: file, function: function, line: line)
    }
    
    func fatal(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.fatal, message, file: file, function: function, line: line)
    }
}

// MARK: - DateFormatter 扩展
extension DateFormatter {
    static let logTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}
