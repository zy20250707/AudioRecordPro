import Foundation
import Darwin
import CoreAudio
import AppKit

// MARK: - AudioProcessInfo 结构体
struct AudioProcessInfo: Hashable {
    let pid: pid_t
    let name: String
    let bundleID: String
    let path: String
    let processObjectID: AudioObjectID
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
        hasher.combine(name)
        hasher.combine(bundleID)
    }
    
    static func == (lhs: AudioProcessInfo, rhs: AudioProcessInfo) -> Bool {
        return lhs.pid == rhs.pid && lhs.name == rhs.name && lhs.bundleID == rhs.bundleID
    }
}

// MARK: - AudioProcessEnumerator
/// 音频进程枚举器 - 负责获取和管理可录制的音频进程列表
class AudioProcessEnumerator {
    
    // MARK: - Properties
    private let logger = Logger.shared
    
    // MARK: - Public Methods
    
    /// 获取所有可用的音频进程列表
    func getAvailableAudioProcesses() -> [AudioProcessInfo] {
        logger.info("🔍 AudioProcessEnumerator: 开始枚举可用音频进程...")
        var results: [AudioProcessInfo] = []

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        // 读取列表大小
        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else {
            logger.error("❌ AudioProcessEnumerator: 读取进程对象列表大小失败: OSStatus=\(status)")
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        logger.info("📊 发现 \(count) 个音频进程对象")

        // 读取进程对象ID数组
        var objectIDs = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objectIDs)
        guard status == noErr else {
            logger.error("❌ AudioProcessEnumerator: 读取进程对象列表失败: OSStatus=\(status)")
            return []
        }

        logger.info("🔍 开始解析每个进程对象...")
        for (index, oid) in objectIDs.enumerated() where oid != kAudioObjectUnknown {
            guard let pid = readPID(for: oid) else { 
                logger.debug("⚠️ 进程对象[\(index)] ID=\(oid): 无法读取PID，跳过")
                continue 
            }
            
            let (name, path) = readNameAndPath(for: pid)
            
            // 跳过被过滤的进程
            if name.isEmpty {
                logger.debug("⚠️ 进程对象[\(index)] PID=\(pid): 被过滤，跳过")
                continue
            }
            
            let bundleID = readBundleID(for: oid) ?? ""

            // 进一步过滤：排除 Helper/Renderer/GPU 等辅助进程（如 Google Chrome Helper）
            if isHelperApp(name: name, bundleID: bundleID, path: path) {
                logger.debug("🧹 过滤 Helper 进程: name=\(name), bundle=\(bundleID), path=\(path)")
                continue
            }
            let info = AudioProcessInfo(
                pid: pid,
                name: name,
                bundleID: bundleID,
                path: path,
                processObjectID: oid
            )
            results.append(info)
            logger.debug("✅ 进程对象[\(index)]: \(name) (PID: \(pid), Bundle: \(bundleID))")
        }

        logger.info("🎉 AudioProcessEnumerator: 枚举完成，返回 \(results.count) 个可用音频进程")
        
        // 输出所有进程的详细信息
        for (index, process) in results.enumerated() {
            logger.info("   [\(index)] \(process.name) (PID: \(process.pid), Bundle: \(process.bundleID), 对象ID: \(process.processObjectID))")
        }
        
        return results
    }
    
    /// 根据 PID 查找进程对象 ID
    func findProcessObjectID(by pid: pid_t) -> AudioObjectID? {
        let processes = getAvailableAudioProcesses()
        return processes.first { $0.pid == pid }?.processObjectID
    }
    
    /// 解析系统混音 PID（coreaudiod 进程）
    func resolveDefaultSystemMixPID() -> pid_t? {
        logger.info("AudioProcessEnumerator: 尝试解析系统混音 PID...")
        
        // 尝试通过 ps 命令查找 coreaudiod 进程
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid,comm"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                logger.warning("AudioProcessEnumerator: 无法解析 ps 输出，使用默认 PID 171")
                return 171
            }
            
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: .whitespaces)
                if parts.count >= 2, let pidStr = parts.first, let pid = Int32(pidStr) {
                    let command = parts[1]
                    if command.contains("coreaudiod") {
                        logger.info("AudioProcessEnumerator: 找到 coreaudiod 进程 PID: \(pid)")
                        return pid
                    }
                }
            }
            
            logger.warning("AudioProcessEnumerator: 未找到 coreaudiod 进程，使用默认 PID 171")
            return 171
            
        } catch {
            logger.error("AudioProcessEnumerator: 执行 ps 命令失败: \(error)，使用默认 PID 171")
            return 171
        }
    }
    
    // MARK: - Private Methods
    
    private func readPID(for objectID: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        let s = AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, &pid)
        return s == noErr && pid > 0 ? pid : nil
    }

    private func readBundleID(for objectID: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfstr: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let s = withUnsafeMutablePointer(to: &cfstr) { ptr -> OSStatus in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
        }
        if s == noErr, let bid = cfstr as String?, !bid.isEmpty { return bid }
        return nil
    }

    private func readNameAndPath(for pid: pid_t) -> (String, String) {
        let nameBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
        let pathBuffer = UnsafeMutablePointer<Int8>.allocate(capacity: Int(MAXPATHLEN))
        defer { nameBuffer.deallocate(); pathBuffer.deallocate() }
        
        let nameLen = proc_name(pid, nameBuffer, UInt32(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        
        var name: String
        var path: String
        
        if nameLen > 0 {
            name = String(cString: nameBuffer)
        } else {
            if pathLen > 0 {
                path = String(cString: pathBuffer)
                name = URL(fileURLWithPath: path).lastPathComponent
                if name.isEmpty {
                    name = "System Process (\(pid))"
                }
            } else {
                name = "System Process (\(pid))"
            }
        }
        
        path = pathLen > 0 ? String(cString: pathBuffer) : ""
        
        let bundlePath = convertToBundlePath(path)
        
        if shouldFilterProcess(name: name, pid: pid, path: bundlePath) {
            return ("", "")
        }
        
        return (name, bundlePath)
    }
    
    private func shouldFilterProcess(name: String, pid: pid_t, path: String) -> Bool {
        let systemProcesses = [
            "kernel_task", "launchd", "kernel", "mach_init",
            "WindowServer", "loginwindow", "sh", "bash", "zsh"
        ]
        
        if systemProcesses.contains(name) {
            return true
        }
        
        if pid < 100 {
            return true
        }
        
        if path.isEmpty {
            return true
        }
        
        let systemPaths = [
            "/System/Library/",
            "/usr/libexec/",
            "/usr/sbin/",
            "/sbin/"
        ]
        
        for systemPath in systemPaths {
            if path.hasPrefix(systemPath) {
                return true
            }
        }
        
        // 仅保留 Dock 应用（ActivationPolicy == .regular）
        if !isDockApp(pid: pid, path: path) {
            return true
        }
        
        return false
    }

    /// 判断是否为浏览器/应用的 Helper、Renderer、GPU 等辅助进程
    private func isHelperApp(name: String, bundleID: String, path: String) -> Bool {
        let n = name.lowercased()
        let b = bundleID.lowercased()
        let p = path.lowercased()

        // 常见关键字
        let keywords = [" helper", "renderer", "gpu", "webhelper", "plugin", "(renderer)"]
        if keywords.contains(where: { n.contains($0) }) { return true }
        if keywords.contains(where: { b.contains($0) }) { return true }

        // 路径特征：在 Helpers 目录下或以 Helper.app 结尾
        if p.contains("/helpers/") || p.hasSuffix("helper.app") { return true }

        // 具体特例：Google Chrome Helper 系列
        if n.contains("google chrome helper") || b.contains("com.google.chrome.helper") { return true }

        // WebKit/GPU 相关（已基本被系统路径过滤，但再兜底一次）
        if n.contains("webkit") && (n.contains("gpu") || n.contains("network") || n.contains("webcontent")) {
            return true
        }
        return false
    }
    
    /// 判断是否为 Dock 应用
    private func isDockApp(pid: pid_t, path: String) -> Bool {
        if let running = NSRunningApplication(processIdentifier: pid) {
            return running.activationPolicy == .regular
        }
        
        let bundleURL = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: bundleURL) {
            if let uiElement = bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, uiElement { return false }
            if let bgOnly = bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool, bgOnly { return false }
            return true
        }
        
        return false
    }
    
    /// 将可执行文件路径转换为 .app bundle 路径
    private func convertToBundlePath(_ executablePath: String) -> String {
        guard !executablePath.isEmpty else { return executablePath }
        
        let url = URL(fileURLWithPath: executablePath)
        var currentURL = url
        
        while currentURL.path != "/" {
            if currentURL.pathExtension == "app" {
                return currentURL.path
            }
            currentURL = currentURL.deletingLastPathComponent()
        }
        
        return executablePath
    }
}
