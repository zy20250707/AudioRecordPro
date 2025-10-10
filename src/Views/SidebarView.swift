import Cocoa
import Foundation

// MARK: - Delegate Protocol
protocol SidebarViewDelegate: AnyObject {
    func sidebarViewDidChangeSourceSelection(_ view: SidebarView)
    func sidebarViewDidSelectProcesses(_ view: SidebarView, pids: [pid_t])
    func sidebarViewDidRequestProcessRefresh(_ view: SidebarView)
    func sidebarViewDidDoubleClickFile(_ view: SidebarView, file: RecordedFileInfo)
    func sidebarViewDidRequestExportToMP3(_ view: SidebarView, file: RecordedFileInfo)
}

// MARK: - SidebarView
/// 侧边栏视图 - 负责音频源选择和进程列表管理，集成Tab切换功能
class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, TabContainerViewDelegate, RecordedFilesViewDelegate {
    
    // MARK: - UI Components
    private let tabContainer = TabContainerView()
    private let audioRecorderTabView = NSView()
    private let recordedFilesTabView = NSView()
    
    // 音频录制Tab的组件
    private let systemHeader = NSTextField()
    private let micHeader = NSTextField()
    private let appsHeader = NSTextField()
    private let systemCheckbox = NSButton(checkboxWithTitle: "系统音频输出", target: nil, action: nil)
    private let microphoneCheckbox = NSButton(checkboxWithTitle: "麦克风", target: nil, action: nil)
    private let mixAudioCheckbox = NSButton(checkboxWithTitle: "实时混音（开发中）", target: nil, action: nil)
    private let refreshButton = NSButton(title: "🔄 刷新", target: nil, action: nil)
    private let appsScroll = NSScrollView()
    private let appsTable = NSTableView()
    private let appsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
    
    // 已录制文件Tab的组件
    private let recordedFilesView = RecordedFilesView()
    
    // MARK: - Properties
    weak var delegate: SidebarViewDelegate?
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedPIDs: [pid_t] = []
    private let logger = Logger.shared
    private var iconCache: [String: NSImage] = [:]
    
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
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        setupTabContainer()
        setupAudioRecorderTab()
        setupRecordedFilesTab()
        setupConstraints()
    }
    
    private func setupTabContainer() {
        tabContainer.delegate = self
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabContainer)
    }
    
    private func setupAudioRecorderTab() {
        // 设置音频录制Tab的内容
        audioRecorderTabView.translatesAutoresizingMaskIntoConstraints = false
        
        setupHeaders()
        setupCheckboxes()
        setupRefreshButton()
        setupAppsTable()
        
        // 添加所有组件到audioRecorderTabView
        audioRecorderTabView.addSubview(systemHeader)
        audioRecorderTabView.addSubview(micHeader)
        audioRecorderTabView.addSubview(appsHeader)
        audioRecorderTabView.addSubview(systemCheckbox)
        audioRecorderTabView.addSubview(microphoneCheckbox)
        audioRecorderTabView.addSubview(mixAudioCheckbox)
        audioRecorderTabView.addSubview(refreshButton)
        audioRecorderTabView.addSubview(appsScroll)
        
        // 创建Tab
        let audioRecorderTab = TabItem(
            id: "audioRecorder",
            title: "Audio Recorder",
            icon: "waveform",
            view: audioRecorderTabView
        )
        tabContainer.addTab(audioRecorderTab)
    }
    
    private func setupRecordedFilesTab() {
        // 设置已录制文件Tab的内容
        recordedFilesTabView.translatesAutoresizingMaskIntoConstraints = false
        
        recordedFilesView.delegate = self
        recordedFilesView.translatesAutoresizingMaskIntoConstraints = false
        recordedFilesTabView.addSubview(recordedFilesView)
        
        NSLayoutConstraint.activate([
            recordedFilesView.topAnchor.constraint(equalTo: recordedFilesTabView.topAnchor),
            recordedFilesView.leadingAnchor.constraint(equalTo: recordedFilesTabView.leadingAnchor),
            recordedFilesView.trailingAnchor.constraint(equalTo: recordedFilesTabView.trailingAnchor),
            recordedFilesView.bottomAnchor.constraint(equalTo: recordedFilesTabView.bottomAnchor)
        ])
        
        // 创建Tab
        let recordedFilesTab = TabItem(
            id: "recordedFiles",
            title: "Saved Files",
            icon: "folder",
            view: recordedFilesTabView
        )
        tabContainer.addTab(recordedFilesTab)
    }
    
    private func setupHeaders() {
        func styleHeader(_ textField: NSTextField, _ title: String) {
            textField.stringValue = title
            textField.isBordered = false
            textField.isEditable = false
            textField.backgroundColor = .clear
            textField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            textField.textColor = NSColor.secondaryLabelColor
            textField.translatesAutoresizingMaskIntoConstraints = false
            addSubview(textField)
        }
        
        styleHeader(systemHeader, "系统音频输出")
        styleHeader(micHeader, "麦克风")
        styleHeader(appsHeader, "已打开的应用")
    }
    
    private func setupCheckboxes() {
        systemCheckbox.target = self
        systemCheckbox.action = #selector(sourceCheckboxChanged)
        systemCheckbox.translatesAutoresizingMaskIntoConstraints = false
        
        microphoneCheckbox.target = self
        microphoneCheckbox.action = #selector(sourceCheckboxChanged)
        microphoneCheckbox.translatesAutoresizingMaskIntoConstraints = false
        
        // 混音开关（预留，暂时禁用）
        mixAudioCheckbox.target = self
        mixAudioCheckbox.action = #selector(mixAudioCheckboxChanged)
        mixAudioCheckbox.translatesAutoresizingMaskIntoConstraints = false
        mixAudioCheckbox.isEnabled = false  // 暂时禁用，功能开发中
        mixAudioCheckbox.toolTip = "实时混音功能开发中，敬请期待"
    }
    
    private func setupRefreshButton() {
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonClicked)
        refreshButton.bezelStyle = .rounded
        refreshButton.font = NSFont.systemFont(ofSize: 12)
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(refreshButton)
    }
    
    private func setupAppsTable() {
        appsColumn.title = "Apps"
        appsTable.addTableColumn(appsColumn)
        appsTable.headerView = nil
        appsTable.rowSizeStyle = .default
        appsTable.usesAlternatingRowBackgroundColors = true
        appsTable.dataSource = self
        appsTable.delegate = self
        appsTable.rowHeight = 36
        appsTable.allowsMultipleSelection = false  // 改为单选模式，录制只能选择一个程序
        appsTable.translatesAutoresizingMaskIntoConstraints = false
        
        appsScroll.documentView = appsTable
        appsScroll.hasVerticalScroller = true
        appsScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appsScroll)
    }
    
    private func setupConstraints() {
        // Tab容器约束
        NSLayoutConstraint.activate([
            tabContainer.topAnchor.constraint(equalTo: topAnchor),
            tabContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabContainer.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // 音频录制Tab内部的约束
        NSLayoutConstraint.activate([
            systemHeader.topAnchor.constraint(equalTo: audioRecorderTabView.topAnchor, constant: 16),
            systemHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            
            systemCheckbox.topAnchor.constraint(equalTo: systemHeader.bottomAnchor, constant: 8),
            systemCheckbox.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            
            micHeader.topAnchor.constraint(equalTo: systemCheckbox.bottomAnchor, constant: 18),
            micHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            
            microphoneCheckbox.topAnchor.constraint(equalTo: micHeader.bottomAnchor, constant: 8),
            microphoneCheckbox.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            
            mixAudioCheckbox.topAnchor.constraint(equalTo: microphoneCheckbox.bottomAnchor, constant: 8),
            mixAudioCheckbox.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            
            appsHeader.topAnchor.constraint(equalTo: mixAudioCheckbox.bottomAnchor, constant: 18),
            appsHeader.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            
            refreshButton.topAnchor.constraint(equalTo: appsHeader.bottomAnchor, constant: 8),
            refreshButton.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 16),
            refreshButton.widthAnchor.constraint(equalToConstant: 80),
            refreshButton.heightAnchor.constraint(equalToConstant: 24),
            
            appsScroll.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 8),
            appsScroll.leadingAnchor.constraint(equalTo: audioRecorderTabView.leadingAnchor, constant: 12),
            appsScroll.trailingAnchor.constraint(equalTo: audioRecorderTabView.trailingAnchor, constant: -12),
            appsScroll.bottomAnchor.constraint(equalTo: audioRecorderTabView.bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Actions
    @objc private func sourceCheckboxChanged() {
        delegate?.sidebarViewDidChangeSourceSelection(self)
    }
    
    @objc private func mixAudioCheckboxChanged() {
        // 预留：混音功能开发中
        logger.info("混音开关状态: \(mixAudioCheckbox.state == .on ? "开启" : "关闭")")
    }
    
    @objc private func refreshButtonClicked() {
        delegate?.sidebarViewDidRequestProcessRefresh(self)
    }
    
    // MARK: - TabContainerViewDelegate
    func tabContainerViewDidSelectTab(_ view: TabContainerView, tabId: String) {
        logger.info("侧边栏切换到Tab: \(tabId)")
    }
    
    // MARK: - RecordedFilesViewDelegate
    func recordedFilesViewDidSelectFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        // 文件被选中，可以在这里添加预览功能
    }
    
    func recordedFilesViewDidDoubleClickFile(_ view: RecordedFilesView, file: RecordedFileInfo) {
        // 双击文件，从Finder中打开
        delegate?.sidebarViewDidDoubleClickFile(self, file: file)
    }
    
    func recordedFilesViewDidRequestExportToMP3(_ view: RecordedFilesView, file: RecordedFileInfo) {
        // 导出为MP3格式
        delegate?.sidebarViewDidRequestExportToMP3(self, file: file)
    }
    
    
    // MARK: - Public Methods
    func updateProcessList(_ processes: [AudioProcessInfo]) {
        availableProcesses = processes
        // 预加载图标到缓存
        preloadIcons(for: processes)
        appsTable.reloadData()
    }
    
    func restoreProcessSelection(_ processes: [AudioProcessInfo]) {
        // 不恢复任何选择，完全重置状态
        logger.info("📝 完全重置UI状态，不恢复任何进程选择")
        
        // 清除所有选择
        appsTable.deselectAll(nil)
        
        // 清除选择状态
        selectedPIDs = []
    }
    
    func isSystemAudioSourceSelected() -> Bool {
        return systemCheckbox.state == .on
    }
    
    func isMicrophoneSourceSelected() -> Bool {
        return microphoneCheckbox.state == .on
    }
    
    func getSelectedProcesses() -> [AudioProcessInfo] {
        let selectedRows = appsTable.selectedRowIndexes
        var selectedProcesses: [AudioProcessInfo] = []
        for index in selectedRows {
            if index < availableProcesses.count {
                selectedProcesses.append(availableProcesses[index])
            }
        }
        return selectedProcesses
    }
    
    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return availableProcesses.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("AppCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.image = NSImage(named: NSImage.multipleDocumentsName)
            imageView.wantsLayer = true
            imageView.layer?.cornerRadius = 4
            cell.addSubview(imageView)
            
            let text = NSTextField(labelWithString: "")
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            
            cell.imageView = imageView
            cell.textField = text
            
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24),
                text.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8)
            ])
        }
        
        if row < availableProcesses.count {
            let process = availableProcesses[row]
            // 常规显示格式
            let displayName = process.name
            let pidText = "PID: \(process.pid)"
            cell.textField?.stringValue = "\(displayName) (\(pidText))"
            cell.textField?.textColor = NSColor.labelColor
            
            // 尝试设置应用图标（使用缓存）
            if !process.path.isEmpty {
                let icon = getCachedIcon(for: process.path)
                cell.imageView?.image = icon
                logger.debug("🎨 设置图标: \(process.name) -> \(process.path)")
            } else {
                logger.debug("⚠️ 进程路径为空，无法加载图标: \(process.name)")
                // 设置默认图标
                cell.imageView?.image = NSImage(named: NSImage.applicationIconName)
            }
        }
        
        return cell
    }
    
    // MARK: - NSTableViewDelegate
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedProcesses = getSelectedProcesses()
        let pids = selectedProcesses.map { $0.pid }
        delegate?.sidebarViewDidSelectProcesses(self, pids: pids)
    }
    
    // MARK: - Private Methods
    private func preloadIcons(for processes: [AudioProcessInfo]) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            for process in processes {
                if !process.path.isEmpty && self.iconCache[process.path] == nil {
                    let icon = NSWorkspace.shared.icon(forFile: process.path)
                    // 调整图标大小以优化性能
                    icon.size = NSSize(width: 24, height: 24)
        icon.size = NSSize(width: 24, height: 24)
                    
                    DispatchQueue.main.async {
                        self.iconCache[process.path] = icon
                        self.logger.debug("🔄 预加载图标: \(process.name) -> \(process.path)")
                    }
                } else if process.path.isEmpty {
                    self.logger.debug("⚠️ 跳过预加载（路径为空）: \(process.name)")
                }
            }
        }
    }
    
    private func getCachedIcon(for path: String) -> NSImage {
        if let cachedIcon = iconCache[path] {
            return cachedIcon
        }
        
        // 如果缓存中没有，立即加载并缓存
        let icon = loadAppIcon(for: path)
        icon.size = NSSize(width: 24, height: 24)
        iconCache[path] = icon
        
        return icon
    }
    
    /// 加载应用图标，支持多种方式
    private func loadAppIcon(for path: String) -> NSImage {
        // 方法1: 直接从 .app bundle 路径加载
        if path.hasSuffix(".app") {
            let icon = NSWorkspace.shared.icon(forFile: path)
            if icon.size.width > 0 && icon.size.height > 0 {
                logger.debug("✅ 从 .app bundle 加载图标成功: \(path)")
                return icon
            }
        }
        
        // 方法2: 尝试从可执行文件路径向上查找 .app bundle
        let bundlePath = findAppBundlePath(from: path)
        if bundlePath != path {
            let icon = NSWorkspace.shared.icon(forFile: bundlePath)
            if icon.size.width > 0 && icon.size.height > 0 {
                logger.debug("✅ 从转换的 bundle 路径加载图标成功: \(bundlePath)")
                return icon
            }
        }
        
        // 方法3: 尝试从 Bundle ID 获取图标
        if let bundleID = getBundleID(from: path) {
            let icon = NSWorkspace.shared.icon(forFile: bundleID)
            if icon.size.width > 0 && icon.size.height > 0 {
                logger.debug("✅ 从 Bundle ID 加载图标成功: \(bundleID)")
                return icon
            }
        }
        
        // 方法4: 使用默认图标
        logger.debug("⚠️ 所有方法都失败，使用默认图标: \(path)")
        return NSImage(named: NSImage.applicationIconName) ?? NSImage(named: NSImage.multipleDocumentsName)!
    }
    
    /// 从可执行文件路径查找 .app bundle 路径
    private func findAppBundlePath(from executablePath: String) -> String {
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
    
    /// 从路径获取 Bundle ID（简化版本）
    private func getBundleID(from path: String) -> String? {
        // 这里可以扩展更复杂的 Bundle ID 获取逻辑
        // 目前返回 nil，让系统使用默认图标
        return nil
    }
    
    /// 刷新已录制文件列表
    func refreshRecordedFiles() {
        recordedFilesView.refreshFiles()
    }
    
    /// 加载录音文件列表（启动时使用）
    func loadRecordedFiles(_ files: [RecordedFileInfo]) {
        recordedFilesView.loadRecordedFiles(files)
    }
    
    /// 添加新的录制文件到列表
    func addRecordedFile(_ file: RecordedFileInfo) {
        recordedFilesView.addRecordedFile(file)
    }
}
