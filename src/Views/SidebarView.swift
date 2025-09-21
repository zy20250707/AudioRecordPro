import Cocoa
import Foundation

// MARK: - Delegate Protocol
protocol SidebarViewDelegate: AnyObject {
    func sidebarViewDidChangeSourceSelection(_ view: SidebarView)
    func sidebarViewDidSelectProcesses(_ view: SidebarView, pids: [pid_t])
    func sidebarViewDidRequestProcessRefresh(_ view: SidebarView)
}

// MARK: - SidebarView
/// 侧边栏视图 - 负责音频源选择和进程列表管理
class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    
    // MARK: - UI Components
    private let systemHeader = NSTextField()
    private let micHeader = NSTextField()
    private let appsHeader = NSTextField()
    private let systemCheckbox = NSButton(checkboxWithTitle: "系统音频输出", target: nil, action: nil)
    private let microphoneCheckbox = NSButton(checkboxWithTitle: "麦克风", target: nil, action: nil)
    private let refreshButton = NSButton(title: "🔄 刷新", target: nil, action: nil)
    private let appsScroll = NSScrollView()
    private let appsTable = NSTableView()
    private let appsColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("app"))
    
    // MARK: - Properties
    weak var delegate: SidebarViewDelegate?
    private var availableProcesses: [AudioProcessInfo] = []
    private var selectedPIDs: [pid_t] = []
    private let logger = Logger.shared
    
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
        
        setupHeaders()
        setupCheckboxes()
        setupRefreshButton()
        setupAppsTable()
        setupConstraints()
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
        addSubview(systemCheckbox)
        
        microphoneCheckbox.target = self
        microphoneCheckbox.action = #selector(sourceCheckboxChanged)
        microphoneCheckbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(microphoneCheckbox)
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
        appsTable.rowHeight = 28
        appsTable.allowsMultipleSelection = false  // 改为单选模式，录制只能选择一个程序
        appsTable.translatesAutoresizingMaskIntoConstraints = false
        
        appsScroll.documentView = appsTable
        appsScroll.hasVerticalScroller = true
        appsScroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appsScroll)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            systemHeader.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            systemHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            systemCheckbox.topAnchor.constraint(equalTo: systemHeader.bottomAnchor, constant: 8),
            systemCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            micHeader.topAnchor.constraint(equalTo: systemCheckbox.bottomAnchor, constant: 18),
            micHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            microphoneCheckbox.topAnchor.constraint(equalTo: micHeader.bottomAnchor, constant: 8),
            microphoneCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            appsHeader.topAnchor.constraint(equalTo: microphoneCheckbox.bottomAnchor, constant: 18),
            appsHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            
            refreshButton.topAnchor.constraint(equalTo: appsHeader.bottomAnchor, constant: 8),
            refreshButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            refreshButton.widthAnchor.constraint(equalToConstant: 80),
            refreshButton.heightAnchor.constraint(equalToConstant: 24),
            
            appsScroll.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 8),
            appsScroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            appsScroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            appsScroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Actions
    @objc private func sourceCheckboxChanged() {
        delegate?.sidebarViewDidChangeSourceSelection(self)
    }
    
    @objc private func refreshButtonClicked() {
        delegate?.sidebarViewDidRequestProcessRefresh(self)
    }
    
    // MARK: - Public Methods
    func updateProcessList(_ processes: [AudioProcessInfo]) {
        availableProcesses = processes
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
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                text.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8)
            ])
        }
        
        if row < availableProcesses.count {
            let process = availableProcesses[row]
            // 改进显示格式，突出显示QQ音乐等音乐应用
            let displayName = process.name
            let pidText = "PID: \(process.pid)"
            
            // 为音乐应用添加特殊标识
            let isMusicApp = process.name.lowercased().contains("music") || 
                           process.name.lowercased().contains("音乐") ||
                           process.bundleID.lowercased().contains("music")
            
            if isMusicApp {
                cell.textField?.stringValue = "🎵 \(displayName) (\(pidText))"
                cell.textField?.textColor = NSColor.systemBlue
            } else {
                cell.textField?.stringValue = "\(displayName) (\(pidText))"
                cell.textField?.textColor = NSColor.labelColor
            }
            
            // 尝试设置应用图标
            if !process.path.isEmpty {
                let icon = NSWorkspace.shared.icon(forFile: process.path)
                cell.imageView?.image = icon
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
}
