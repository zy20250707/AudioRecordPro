import Foundation
import AVFoundation

/// AudioRecord SDK 测试运行器
@available(macOS 14.4, *)
@MainActor
class SDKTestRunner {
    
    private let audioAPI = AudioAPI.shared
    private var testResults: [String] = []
    
    // MARK: - 主测试入口
    
    /// 运行所有测试
    func runAllTests() async {
        print("🧪 开始 AudioRecord SDK 测试...")
        print("=" * 50)
        
        // 清空之前的测试结果
        testResults.removeAll()
        
        // 运行各项测试
        await testSDKInfo()
        await testConstraintsCreation()
        await testErrorHandling()
        await testPermissionCheck()
        await testMicrophonePermissionCheckOnly()
        await testMicrophonePermissionRequestFlow()
        await testMicrophoneRecording()
        await testMixedRecording()
        await testStreamManagement()
        
        // 输出测试总结
        printTestSummary()
    }
    
    // MARK: - 具体测试方法
    
    /// 测试 SDK 信息
    private func testSDKInfo() async {
        print("\n📋 测试 SDK 信息...")
        
        do {
            // 测试 SDK 信息输出
            AudioRecordSDKInfo.printInfo()
            
            // 验证版本信息
            assert(AudioRecordSDKInfo.version == "1.0.0", "版本号不正确")
            assert(AudioRecordSDKInfo.name == "AudioRecordSDK", "SDK 名称不正确")
            
            addTestResult("✅ SDK 信息测试通过")
            
        } catch {
            addTestResult("❌ SDK 信息测试失败: \(error)")
        }
    }
    
    /// 测试约束创建
    private func testConstraintsCreation() async {
        print("\n🔧 测试约束创建...")
        
        do {
            // 测试麦克风约束
            let micConstraints = createMicrophoneConstraints(
                echoCancellation: true,
                noiseSuppression: false
            )
            
            assert(micConstraints.sampleRate == 48000, "采样率不正确")
            assert(micConstraints.channelCount == 2, "声道数不正确")
            assert(micConstraints.echoCancellation == true, "回声消除设置不正确")
            assert(micConstraints.noiseSuppression == false, "噪音抑制设置不正确")
            assert(micConstraints.includeSystemAudio == false, "系统音频设置不正确")
            
            // 测试混音约束
            let mixedConstraints = createMixedAudioConstraints(
                echoCancellation: false,
                noiseSuppression: true
            )
            
            assert(mixedConstraints.includeSystemAudio == true, "混音约束系统音频设置不正确")
            assert(mixedConstraints.echoCancellation == false, "混音约束回声消除设置不正确")
            assert(mixedConstraints.noiseSuppression == true, "混音约束噪音抑制设置不正确")
            
            addTestResult("✅ 约束创建测试通过")
            
        } catch {
            addTestResult("❌ 约束创建测试失败: \(error)")
        }
    }
    
    /// 测试错误处理
    private func testErrorHandling() async {
        print("\n⚠️ 测试错误处理...")
        
        do {
            // 测试各种错误类型
            let errors: [AudioError] = [
                .microphonePermissionDenied,
                .systemAudioPermissionDenied,
                .deviceNotFound,
                .alreadyRecording,
                .notSupported("测试功能"),
                .unknown(NSError(domain: "test", code: 0))
            ]
            
            for error in errors {
                let description = error.localizedDescription
                assert(!description.isEmpty, "错误描述不能为空")
                print("  - \(error): \(description)")
            }
            
            addTestResult("✅ 错误处理测试通过")
            
        } catch {
            addTestResult("❌ 错误处理测试失败: \(error)")
        }
    }
    
    /// 测试权限检查
    private func testPermissionCheck() async {
        print("\n🔐 测试权限检查...")
        
        do {
            // 检查当前麦克风权限状态
            let currentStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            print("  当前麦克风权限状态: \(currentStatus.rawValue)")
            
            switch currentStatus {
            case .authorized:
                print("  ✅ 麦克风权限已授权")
            case .denied:
                print("  ❌ 麦克风权限被拒绝")
            case .restricted:
                print("  ⚠️ 麦克风权限受限")
            case .notDetermined:
                print("  ❓ 麦克风权限未确定")
            @unknown default:
                print("  ❓ 未知权限状态")
            }
            
            addTestResult("✅ 权限检查测试通过")
            
        } catch {
            addTestResult("❌ 权限检查测试失败: \(error)")
        }
    }

    /// 只检查麦克风权限（不弹窗）
    private func testMicrophonePermissionCheckOnly() async {
        print("\n🔎 测试麦克风权限（只检查，不弹窗）...")
        do {
            let status = PermissionManager.shared.getMicrophonePermissionStatus()
            switch status {
            case .granted:
                print("  ✅ 当前已授权")
            case .denied:
                print("  ❌ 当前已被拒绝")
            case .restricted:
                print("  ⚠️ 当前受限制")
            case .notDetermined:
                print("  ❓ 当前未决定（本测试不弹窗）")
            }
            addTestResult("✅ 麦克风权限静默检查测试通过")
        } catch {
            addTestResult("❌ 麦克风权限静默检查测试失败: \(error)")
        }
    }

    /// 未决定时申请麦克风权限（可能弹窗）
    private func testMicrophonePermissionRequestFlow() async {
        print("\n🪪 测试麦克风权限申请流程（未决定时会弹窗）...")
        do {
            let status = PermissionManager.shared.getMicrophonePermissionStatus()
            if status == .notDetermined {
                print("  ⏳ 当前未决定，开始申请...")
                let granted = await PermissionManager.shared.requestMicrophonePermissionAsync()
                print("  结果: \(granted ? "✅ 已授权" : "❌ 被拒绝")")
                addTestResult(granted ? "✅ 麦克风权限申请测试通过" : "⚠️ 麦克风权限申请测试-用户拒绝")
            } else {
                print("  ℹ️ 当前状态非未决定（跳过申请）：\(status)")
                addTestResult("⚠️ 麦克风权限申请测试跳过 - 非未决定状态")
            }
        } catch {
            addTestResult("❌ 麦克风权限申请测试失败: \(error)")
        }
    }

    /// 只检查系统音频捕获权限（不弹窗）
    private func testSystemAudioPermissionCheckOnly() async {
        print("\n🎧 测试系统音频权限（只检查，不弹窗）...")
        let status = PermissionManager.shared.getSystemAudioCapturePermissionStatus()
        let desc = PermissionManager.shared.getPermissionStatusDescription(status)
        print("  当前系统音频权限: \(desc)")
        addTestResult("✅ 系统音频权限静默检查测试通过")
    }

    /// 申请系统音频捕获权限（可能弹窗）
    private func testSystemAudioPermissionRequestFlow() async {
        print("\n🔊 测试系统音频权限申请流程（可能弹窗）...")
        let before = PermissionManager.shared.getSystemAudioCapturePermissionStatus()
        if before == .notDetermined {
            print("  ⏳ 当前未决定，开始申请...")
            let result = await PermissionManager.shared.requestSystemAudioCapturePermissionAsync()
            let desc = PermissionManager.shared.getPermissionStatusDescription(result)
            print("  结果: \(desc)")
            addTestResult(result == .granted ? "✅ 系统音频权限申请测试通过" : "⚠️ 系统音频权限申请测试-未授权")
        } else {
            let desc = PermissionManager.shared.getPermissionStatusDescription(before)
            print("  ℹ️ 当前状态为 \(desc)（跳过申请）")
            addTestResult("⚠️ 系统音频权限申请测试跳过 - 非未决定状态")
        }
    }
    
    /// 测试麦克风录制流程
    private func testMicrophoneRecording() async {
        print("\n🎤 测试麦克风录制流程...")
        
        do {
            // 创建约束
            let constraints = createMicrophoneConstraints()
            
            // 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            
            // 验证流属性
            assert(!stream.id.isEmpty, "流 ID 不能为空")
            assert(stream.recordingMode == "microphone", "录制模式不正确")
            
            // 验证轨道
            let tracks = stream.getAudioTracks()
            assert(tracks.count == 1, "轨道数量不正确")
            
            let track = tracks.first!
            assert(track.kind == "audio", "轨道类型不正确")
            assert(track.label == "Microphone Track", "轨道标签不正确")
            assert(track.enabled == true, "轨道应该是启用状态")
            assert(track.readyState == .live, "轨道应该是活跃状态")
            
            // 测试不支持的方法
            do {
                try stream.addTrack(track)
                addTestResult("❌ addTrack 应该抛出错误")
            } catch AudioError.notSupported {
                // 预期的错误
            }
            
            do {
                try track.applyConstraints([:])
                addTestResult("❌ applyConstraints 应该抛出错误")
            } catch AudioError.notSupported {
                // 预期的错误
            }
            
            addTestResult("✅ 麦克风录制流程测试通过")
            
        } catch AudioError.microphonePermissionDenied {
            addTestResult("⚠️ 麦克风录制测试跳过 - 权限被拒绝")
        } catch {
            addTestResult("❌ 麦克风录制测试失败: \(error)")
        }
    }
    
    /// 测试混音录制流程
    private func testMixedRecording() async {
        print("\n🎵 测试混音录制流程...")
        
        do {
            // 创建混音约束
            let constraints = createMixedAudioConstraints()
            
            // 获取媒体流
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            
            // 验证流属性
            assert(stream.recordingMode == "mixed", "混音录制模式不正确")
            
            // 验证轨道
            let tracks = stream.getAudioTracks()
            let track = tracks.first!
            assert(track.label == "Mixed Audio Track", "混音轨道标签不正确")
            
            addTestResult("✅ 混音录制流程测试通过")
            
        } catch AudioError.microphonePermissionDenied {
            addTestResult("⚠️ 混音录制测试跳过 - 麦克风权限被拒绝")
        } catch AudioError.systemAudioPermissionDenied {
            addTestResult("⚠️ 混音录制测试跳过 - 系统音频权限被拒绝")
        } catch {
            addTestResult("❌ 混音录制测试失败: \(error)")
        }
    }
    
    /// 测试流管理
    private func testStreamManagement() async {
        print("\n📊 测试流管理...")
        
        do {
            // 测试录制状态
            let initialRecordingState = audioAPI.isRecording
            assert(initialRecordingState == false, "初始录制状态应该为 false")
            
            // 测试回调设置
            var levelCallbackCalled = false
            var statusCallbackCalled = false
            
            audioAPI.onLevel = { level in
                levelCallbackCalled = true
                print("  📊 音频电平回调: \(level)")
            }
            
            audioAPI.onStatus = { status in
                statusCallbackCalled = true
                print("  📝 状态回调: \(status)")
            }
            
            audioAPI.onRecordingComplete = { recording in
                print("  ✅ 录制完成回调: \(recording.fileName)")
            }
            
            addTestResult("✅ 流管理测试通过")
            
        } catch {
            addTestResult("❌ 流管理测试失败: \(error)")
        }
    }
    
    // MARK: - 实际录制测试 (可选)
    
    /// 进行麦克风录制测试
    func runMicrophoneOnlyTest(duration: TimeInterval = 3.0) async {
        print("\n🎤 开始麦克风录制测试 (时长: \(duration) 秒)...")
        print("💡 请对着麦克风说话测试录制效果")
        
        do {
            // 设置回调
            setupTestCallbacks()
            
            // 创建麦克风约束
            let micConstraints = createMicrophoneConstraints(
                echoCancellation: true,
                noiseSuppression: true
            )
            
            // 获取麦克风流
            let micStream = try await audioAPI.getUserMedia(constraints: micConstraints)
            
            print("  📊 麦克风流信息:")
            print("    - 流ID: \(micStream.id)")
            print("    - 录制模式: \(micStream.recordingMode)")
            print("    - 轨道数: \(micStream.getAudioTracks().count)")
            
            // 开始录制
            try audioAPI.startRecording(stream: micStream)
            print("  ▶️ 麦克风录制开始...")
            
            // 等待指定时长
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            audioAPI.stopRecording()
            print("  ⏹️ 麦克风录制停止")
            
            // 等待回调完成
            try await Task.sleep(nanoseconds: 500_000_000)
            
            addTestResult("✅ 麦克风录制测试完成")
            
        } catch {
            addTestResult("❌ 麦克风录制测试失败: \(error)")
        }
    }
    
    /// 进行混音录制测试 (系统音频 + 麦克风)
    func runMixedRecordingTest(duration: TimeInterval = 5.0) async {
        print("\n🎵 开始混音录制测试 (时长: \(duration) 秒)...")
        print("💡 请确保:")
        print("   1. 播放一些音乐或音频")
        print("   2. 对着麦克风说话")
        print("   3. 这样可以测试系统音频和麦克风的混音效果")
        
        do {
            // 设置回调
            setupTestCallbacks()
            
            // 创建混音约束
            let mixedConstraints = createMixedAudioConstraints(
                echoCancellation: true,
                noiseSuppression: false  // 混音时通常不需要噪音抑制
            )
            
            // 获取混音流
            let mixedStream = try await audioAPI.getUserMedia(constraints: mixedConstraints)
            
            print("  📊 混音流信息:")
            print("    - 流ID: \(mixedStream.id)")
            print("    - 录制模式: \(mixedStream.recordingMode)")
            print("    - 轨道数: \(mixedStream.getAudioTracks().count)")
            
            // 开始录制
            try audioAPI.startRecording(stream: mixedStream)
            print("  ▶️ 混音录制开始...")
            
            // 等待指定时长
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            audioAPI.stopRecording()
            print("  ⏹️ 混音录制停止")
            
            // 等待回调完成
            try await Task.sleep(nanoseconds: 500_000_000)
            
            addTestResult("✅ 混音录制测试完成")
            
        } catch {
            addTestResult("❌ 混音录制测试失败: \(error)")
        }
    }
    
    /// 进行实际录制测试 (需要用户权限)
    func runActualRecordingTest(duration: TimeInterval = 3.0) async {
        print("\n🎬 开始实际录制测试 (时长: \(duration) 秒)...")
        
        do {
            // 设置回调
            setupTestCallbacks()
            
            // 测试麦克风录制
            print("  🎤 测试麦克风录制...")
            let micConstraints = createMicrophoneConstraints()
            let micStream = try await audioAPI.getUserMedia(constraints: micConstraints)
            
            try audioAPI.startRecording(stream: micStream)
            print("  ▶️ 麦克风录制开始...")
            
            // 等待指定时长
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            audioAPI.stopRecording()
            print("  ⏹️ 麦克风录制停止")
            
            // 等待一下让回调完成
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            // 测试混音录制 (系统音频 + 麦克风)
            print("\n  🎵 测试混音录制 (系统音频 + 麦克风)...")
            let mixedConstraints = createMixedAudioConstraints()
            let mixedStream = try await audioAPI.getUserMedia(constraints: mixedConstraints)
            
            try audioAPI.startRecording(stream: mixedStream)
            print("  ▶️ 混音录制开始...")
            print("  💡 请播放一些音乐或音频，同时对着麦克风说话...")
            
            // 等待指定时长
            try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            audioAPI.stopRecording()
            print("  ⏹️ 混音录制停止")
            
            // 等待一下让回调完成
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5秒
            
            addTestResult("✅ 实际录制测试完成 (麦克风 + 混音)")
            
        } catch {
            addTestResult("❌ 实际录制测试失败: \(error)")
        }
    }
    
    // MARK: - 辅助方法
    
    private func setupTestCallbacks() {
        audioAPI.onLevel = { level in
            if level > 0.1 {
                print("  📊 检测到音频信号: \(String(format: "%.2f", level))")
            }
        }
        
        audioAPI.onStatus = { status in
            print("  📝 状态更新: \(status)")
        }
        
        audioAPI.onRecordingComplete = { recording in
            print("  ✅ 录制完成:")
            print("    - 文件名: \(recording.fileName)")
            print("    - 时长: \(recording.formattedDuration)")
            print("    - 大小: \(recording.formattedFileSize)")
            print("    - 模式: \(recording.recordingModeDisplayName)")
        }
    }
    
    private func addTestResult(_ result: String) {
        testResults.append(result)
        print(result)
    }
    
    private func printTestSummary() {
        print("\n" + "=" * 50)
        print("📊 测试总结:")
        print("=" * 50)
        
        let passedTests = testResults.filter { $0.contains("✅") }
        let failedTests = testResults.filter { $0.contains("❌") }
        let skippedTests = testResults.filter { $0.contains("⚠️") }
        
        print("总测试数: \(testResults.count)")
        print("通过: \(passedTests.count) ✅")
        print("失败: \(failedTests.count) ❌")
        print("跳过: \(skippedTests.count) ⚠️")
        
        if failedTests.isEmpty {
            print("\n🎉 所有测试通过！SDK 工作正常。")
        } else {
            print("\n⚠️ 有测试失败，请检查以下问题:")
            failedTests.forEach { print("  \($0)") }
        }
        
        print("=" * 50)
    }
}

// MARK: - 字符串扩展 (用于重复字符)
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}
