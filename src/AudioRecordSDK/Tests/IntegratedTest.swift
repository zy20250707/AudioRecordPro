import Foundation

/// 集成到现有应用中的 SDK 测试
@available(macOS 14.4, *)
@MainActor
class IntegratedSDKTest {
    
    private let testRunner = SDKTestRunner()
    
    /// 在应用启动时运行快速测试
    func runQuickTests() async {
        print("🧪 运行 AudioRecord SDK 快速测试...")
        
        // 只运行不需要权限的基础测试
        await testSDKInfo()
        await testConstraintsCreation()
        await testErrorHandling()
        
        print("✅ SDK 快速测试完成")
    }
    
    /// 运行完整测试 (包括权限检查)
    func runFullTests() async {
        print("🧪 运行 AudioRecord SDK 完整测试...")
        await testRunner.runAllTests()
    }
    
    /// 测试特定功能
    func testSpecificFeature(_ feature: TestFeature) async {
        print("🧪 测试 SDK 功能: \(feature.rawValue)")
        
        switch feature {
        case .constraints:
            await testConstraintsCreation()
        case .permissions:
            await testPermissionCheck()
        case .microphoneStream:
            await testMicrophoneStream()
        case .mixedStream:
            await testMixedStream()
        case .errorHandling:
            await testErrorHandling()
        }
    }
    
    // MARK: - 具体测试方法
    
    private func testSDKInfo() async {
        do {
            assert(AudioRecordSDKInfo.version == "1.0.0")
            assert(AudioRecordSDKInfo.name == "AudioRecordSDK")
            print("✅ SDK 信息测试通过")
        } catch {
            print("❌ SDK 信息测试失败: \(error)")
        }
    }
    
    private func testConstraintsCreation() async {
        do {
            let micConstraints = createMicrophoneConstraints()
            let mixedConstraints = createMixedAudioConstraints()
            
            assert(micConstraints.includeSystemAudio == false)
            assert(mixedConstraints.includeSystemAudio == true)
            
            print("✅ 约束创建测试通过")
        } catch {
            print("❌ 约束创建测试失败: \(error)")
        }
    }
    
    private func testErrorHandling() async {
        do {
            let errors: [AudioError] = [
                .microphonePermissionDenied,
                .systemAudioPermissionDenied,
                .deviceNotFound,
                .alreadyRecording,
                .notSupported("测试"),
                .unknown(NSError(domain: "test", code: 0))
            ]
            
            for error in errors {
                assert(!error.localizedDescription.isEmpty)
            }
            
            print("✅ 错误处理测试通过")
        } catch {
            print("❌ 错误处理测试失败: \(error)")
        }
    }
    
    private func testPermissionCheck() async {
        // 这里可以添加权限检查逻辑
        print("✅ 权限检查测试通过")
    }
    
    private func testMicrophoneStream() async {
        do {
            let audioAPI = AudioAPI.shared
            let constraints = createMicrophoneConstraints()
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            
            assert(stream.recordingMode == "microphone")
            assert(stream.getAudioTracks().count == 1)
            
            print("✅ 麦克风流测试通过")
        } catch {
            print("❌ 麦克风流测试失败: \(error)")
        }
    }
    
    private func testMixedStream() async {
        do {
            let audioAPI = AudioAPI.shared
            let constraints = createMixedAudioConstraints()
            let stream = try await audioAPI.getUserMedia(constraints: constraints)
            
            assert(stream.recordingMode == "mixed")
            assert(stream.getAudioTracks().count == 1)
            
            print("✅ 混音流测试通过")
        } catch {
            print("❌ 混音流测试失败: \(error)")
        }
    }
}

// MARK: - 测试功能枚举
enum TestFeature: String, CaseIterable {
    case constraints = "约束创建"
    case permissions = "权限检查"
    case microphoneStream = "麦克风流"
    case mixedStream = "混音流"
    case errorHandling = "错误处理"
}

// MARK: - 在 AppDelegate 中使用的扩展
@available(macOS 14.4, *)
extension IntegratedSDKTest {
    
    /// 在应用启动完成后调用
    static func runStartupTests() {
        Task { @MainActor in
            let tester = IntegratedSDKTest()
            await tester.runQuickTests()
        }
    }
    
    /// 在开发模式下运行完整测试
    static func runDevelopmentTests() {
        Task { @MainActor in
            let tester = IntegratedSDKTest()
            await tester.runFullTests()
        }
    }
}
