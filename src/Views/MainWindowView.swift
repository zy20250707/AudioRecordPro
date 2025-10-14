import Cocoa
import Foundation

// MARK: - MainWindowView (重构版本)
/// 主窗口视图 - 使用组件化架构
class MainWindowView: NSView {
    
    // MARK: - UI Components
    private let splitView = NSSplitView()
    private let sidebarView = SidebarView()
    private let contentView = NSView()
    private let tracksView = TracksView()
    private let controlPanelView = ControlPanelView()
    private let statusBarView = StatusBarView()
    
    // MARK: - Properties
    weak var delegate: MainWindowViewDelegate?
    private var availableProcesses: [AudioProcessInfo] = []
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // 背景色
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        
        setupSplitView()
        setupSidebar()
        setupContentView()
        setupConstraints()
    }
    
    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(splitView)
    }
    
    private func setupSidebar() {
        sidebarView.delegate = self
        sidebarView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(sidebarView)
    }
    
    private func setupContentView() {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.white.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(contentView)
        
        // 添加轨道视图
        tracksView.delegate = self
        tracksView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tracksView)
        
        // 添加控制面板
        controlPanelView.delegate = self
        controlPanelView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(controlPanelView)
        
        // 添加状态栏
        statusBarView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusBarView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // SplitView 约束
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),
            sidebarView.widthAnchor.constraint(equalToConstant: 300),
            
            // 轨道视图约束
            tracksView.topAnchor.constraint(equalTo: contentView.topAnchor),
            tracksView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tracksView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tracksView.bottomAnchor.constraint(equalTo: controlPanelView.topAnchor),
            
            // 控制面板约束
            controlPanelView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            controlPanelView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            controlPanelView.bottomAnchor.constraint(equalTo: statusBarView.topAnchor),
            controlPanelView.heightAnchor.constraint(equalToConstant: 120),
            
            // 状态栏约束
            statusBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            statusBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            statusBarView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            statusBarView.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    // MARK: - Public Methods (保持与原有接口兼容)
    func updateStatus(_ status: String) {
        statusBarView.updateStatus(status)
    }
    
    func updateTimer(_ timeString: String) {
        controlPanelView.updateTimer(timeString)
    }
    
    func updateLevel(_ level: Float) {
        tracksView.updateLevel(level)
    }
    
    func updateMode(_ mode: AudioUtils.RecordingMode) {
        // 预留：后续可扩展
    }
    
    func updateRecordingState(_ state: RecordingState) {
        controlPanelView.updateRecordingState(state)
    }
    
    func updateProcessList(_ processes: [AudioProcessInfo]) {
        availableProcesses = processes
        sidebarView.updateProcessList(processes)
    }
    
    func restoreProcessSelection(_ processes: [AudioProcessInfo]) {
        sidebarView.restoreProcessSelection(processes)
    }
    
    func updateTracksDisplay() {
        var tracks: [TrackInfo] = []
        
        // 系统音频
        if sidebarView.isSystemAudioSourceSelected() {
            tracks.append(TrackInfo(icon: "🔊", title: "系统音频输出", isActive: true))
        }
        
        // 麦克风
        if sidebarView.isMicrophoneSourceSelected() {
            tracks.append(TrackInfo(icon: "🎤", title: "麦克风", isActive: true))
        }
        
        // 进程 - 使用应用图标
        let selectedProcesses = sidebarView.getSelectedProcesses()
        for process in selectedProcesses {
            let appIcon = sidebarView.getIconForProcess(process)
            tracks.append(TrackInfo(icon: "", title: process.name, isActive: true, appIcon: appIcon))
        }
        
        tracksView.updateTracks(tracks)
    }
    
    func debugButtonPosition() {
        // 空实现，保持兼容性
    }
    
    // MARK: - Public Query APIs
    func isSystemAudioSourceSelected() -> Bool {
        return sidebarView.isSystemAudioSourceSelected()
    }
    
    func isMicrophoneSourceSelected() -> Bool {
        return sidebarView.isMicrophoneSourceSelected()
    }
    
    func addRecordedFile(_ file: RecordedFileInfo) {
        sidebarView.addRecordedFile(file)
    }
    
    func refreshRecordedFiles() {
        sidebarView.refreshRecordedFiles()
    }
    
    func loadRecordedFiles(_ files: [RecordedFileInfo]) {
        sidebarView.loadRecordedFiles(files)
    }
}

// MARK: - SidebarViewDelegate
extension MainWindowView: SidebarViewDelegate {
    func sidebarViewDidChangeSourceSelection(_ view: SidebarView) {
        updateTracksDisplay()
    }
    
    func sidebarViewDidSelectProcesses(_ view: SidebarView, pids: [pid_t]) {
        delegate?.mainWindowViewDidSelectProcesses(self, pids: pids)
        updateTracksDisplay()
    }
    
    func sidebarViewDidRequestProcessRefresh(_ view: SidebarView) {
        delegate?.mainWindowViewDidRequestProcessRefresh(self)
    }
    
    func sidebarViewDidDoubleClickFile(_ view: SidebarView, file: RecordedFileInfo) {
        // 在Finder中打开文件所在目录并选中该文件
        NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: file.url.deletingLastPathComponent().path)
    }
    
    func sidebarViewDidRequestExportToMP3(_ view: SidebarView, file: RecordedFileInfo) {
        // 导出为MP3格式
        delegate?.mainWindowViewDidRequestExportToMP3(self, file: file)
    }
    
    func sidebarViewDidChangeMixAudio(_ view: SidebarView, enabled: Bool) {
        // 混音状态变化，传递给主控制器
        delegate?.mainWindowViewDidChangeMixAudio(self, enabled: enabled)
    }
}

// MARK: - TracksViewDelegate
extension MainWindowView: TracksViewDelegate {
    func tracksViewDidUpdateTracks(_ view: TracksView, tracks: [TrackInfo]) {
        // 轨道更新完成，可以在这里处理额外的逻辑
    }
}

// MARK: - ControlPanelViewDelegate
extension MainWindowView: ControlPanelViewDelegate {
    func controlPanelViewDidStartRecording(_ view: ControlPanelView) {
        delegate?.mainWindowViewDidStartRecording(self)
    }
    
    func controlPanelViewDidStopRecording(_ view: ControlPanelView) {
        delegate?.mainWindowViewDidStopRecording(self)
    }
}

// MARK: - Delegate Protocol
protocol MainWindowViewDelegate: AnyObject {
    func mainWindowViewDidSwitchMode(_ view: MainWindowView)
    func mainWindowViewDidStartRecording(_ view: MainWindowView)
    func mainWindowViewDidStopRecording(_ view: MainWindowView)
    func mainWindowViewDidPlayRecording(_ view: MainWindowView)
    func mainWindowViewDidDownloadRecording(_ view: MainWindowView)
    func mainWindowViewDidChangeFormat(_ view: MainWindowView, format: String)
    func mainWindowViewDidOpenPermissions(_ view: MainWindowView)
    func mainWindowViewDidStopPlayback(_ view: MainWindowView)
    func mainWindowViewDidSelectProcesses(_ view: MainWindowView, pids: [pid_t])
    func mainWindowViewDidRequestProcessRefresh(_ view: MainWindowView)
    func mainWindowViewDidRequestExportToMP3(_ view: MainWindowView, file: RecordedFileInfo)
    func mainWindowViewDidChangeMixAudio(_ view: MainWindowView, enabled: Bool)
}
