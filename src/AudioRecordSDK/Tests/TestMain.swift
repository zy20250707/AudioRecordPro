import Foundation

/// AudioRecord SDK 测试主程序
@available(macOS 14.4, *)
@main
struct SDKTestMain {
    static func main() async {
        print("🚀 AudioRecord SDK 测试程序启动")
        
        let testRunner = await SDKTestRunner()
        
        // 运行基础测试
        await testRunner.runAllTests()
        
        // 询问进行哪种录制测试
        print("\n❓ 选择录制测试类型:")
        print("  1) 跳过录制测试")
        print("  2) 麦克风录制测试")
        print("  3) 混音录制测试 (系统音频 + 麦克风)")
        print("  4) 完整录制测试 (麦克风 + 混音)")
        print("请输入选择 (1-4):")
        
        if let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) {
            switch input {
            case "2":
                print("🎤 开始麦克风录制测试...")
                await testRunner.runMicrophoneOnlyTest(duration: 3.0)
            case "3":
                print("🎵 开始混音录制测试...")
                await testRunner.runMixedRecordingTest(duration: 5.0)
            case "4":
                print("🎬 开始完整录制测试...")
                await testRunner.runActualRecordingTest(duration: 3.0)
            default:
                print("⏭️ 跳过录制测试")
            }
        } else {
            print("⏭️ 跳过录制测试")
        }
        
        print("\n👋 测试程序结束")
    }
}
