import Cocoa
import Foundation
import AVFoundation

// RecordedFileInfo 已移动到 AudioRecordKit/Sources/API/Types.swift

// MARK: - Delegate Protocol
protocol RecordedFilesViewDelegate: AnyObject {
    func recordedFilesViewDidSelectFile(_ view: RecordedFilesView, file: RecordedFileInfo)
    func recordedFilesViewDidDoubleClickFile(_ view: RecordedFilesView, file: RecordedFileInfo)
    func recordedFilesViewDidRequestExportToMP3(_ view: RecordedFilesView, file: RecordedFileInfo)
}

// MARK: - RecordedFilesView
/// 已录制文件列表视图
class RecordedFilesView: NSView {
    
    // MARK: - UI Components
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
    private let exportButton = NSButton()
    
    // MARK: - Properties
    weak var delegate: RecordedFilesViewDelegate?
    private var recordedFiles: [RecordedFileInfo] = []
    private var selectedFile: RecordedFileInfo?
    private let logger = Logger.shared
    
    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        loadRecordedFiles()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
        loadRecordedFiles()
    }
    
    private func setupView() {
        // 背景色
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        
        setupTableView()
        setupExportButton()
        setupConstraints()
    }
    
    private func setupTableView() {
        // 配置表格视图
        tableView.headerView = nil // 隐藏表头
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 60
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.selectionHighlightStyle = .regular
        tableView.target = self
        tableView.doubleAction = #selector(tableViewDoubleClicked)
        
        // 配置列
        tableColumn.width = 280
        tableColumn.minWidth = 200
        tableColumn.maxWidth = 400
        tableView.addTableColumn(tableColumn)
        
        // 设置数据源和委托
        tableView.dataSource = self
        tableView.delegate = self
        
        // 配置滚动视图
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(scrollView)
    }
    
    private func setupExportButton() {
        // 配置导出按钮
        exportButton.title = "生成 MP3"
        exportButton.target = self
        exportButton.action = #selector(exportButtonClicked)
        exportButton.isEnabled = false
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        
        addSubview(exportButton)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // 表格视图约束
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: exportButton.topAnchor, constant: -8),
            
            // 导出按钮约束
            exportButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            exportButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            exportButton.widthAnchor.constraint(equalToConstant: 100),
            exportButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }
    
    // MARK: - Public Methods
    
    /// 刷新文件列表
    func refreshFiles() {
        loadRecordedFiles()
        tableView.reloadData()
    }
    
    /// 添加新的录制文件
    func addRecordedFile(_ file: RecordedFileInfo) {
        recordedFiles.insert(file, at: 0) // 新文件添加到顶部
        tableView.insertRows(at: IndexSet(integer: 0), withAnimation: .slideDown)
    }
    
    /// 加载录音文件列表（启动时使用）
    func loadRecordedFiles(_ files: [RecordedFileInfo]) {
        recordedFiles = files
        tableView.reloadData()
        logger.info("已加载 \(files.count) 个录音文件到列表")
    }
    
    // MARK: - Private Methods
    
    private func loadRecordedFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsPath = documentsPath.appendingPathComponent("AudioRecordings")
        
        var files: [RecordedFileInfo] = []
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: recordingsPath, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])
            
            for url in fileURLs {
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let fileSize = resourceValues.fileSize ?? 0
                let creationDate = resourceValues.creationDate ?? Date()
                
                // 获取音频文件时长
                let duration = getAudioFileDuration(url: url)
                
                let fileInfo = RecordedFileInfo(
                    url: url,
                    name: url.lastPathComponent,
                    date: creationDate,
                    duration: duration,
                    size: Int64(fileSize)
                )
                
                files.append(fileInfo)
            }
            
            // 按日期排序（最新的在前）
            files.sort { $0.date > $1.date }
            
        } catch {
            logger.error("加载录制文件失败: \(error.localizedDescription)")
        }
        
        recordedFiles = files
    }
    
    private func getAudioFileDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            return Double(audioFile.length) / audioFile.fileFormat.sampleRate
        } catch {
            logger.warning("无法获取音频文件时长: \(error.localizedDescription)")
            return 0
        }
    }
    
    @objc private func tableViewDoubleClicked() {
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0 && selectedRow < recordedFiles.count else { return }
        
        let file = recordedFiles[selectedRow]
        delegate?.recordedFilesViewDidDoubleClickFile(self, file: file)
    }
    
    @objc private func exportButtonClicked() {
        guard let selectedFile = selectedFile else { return }
        delegate?.recordedFilesViewDidRequestExportToMP3(self, file: selectedFile)
    }
}

// MARK: - NSTableViewDataSource
extension RecordedFilesView: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return recordedFiles.count
    }
}

// MARK: - NSTableViewDelegate
extension RecordedFilesView: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < recordedFiles.count else { return nil }
        
        let file = recordedFiles[row]
        
        // 创建文件信息视图
        let fileView = FileInfoView()
        fileView.configure(with: file)
        
        return fileView
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        if selectedRow >= 0 && selectedRow < recordedFiles.count {
            selectedFile = recordedFiles[selectedRow]
            exportButton.isEnabled = true
            delegate?.recordedFilesViewDidSelectFile(self, file: selectedFile!)
        } else {
            selectedFile = nil
            exportButton.isEnabled = false
        }
    }
}

// MARK: - FileInfoView
/// 文件信息显示视图
class FileInfoView: NSView {
    
    private let nameLabel = NSTextField()
    private let dateLabel = NSTextField()
    private let durationLabel = NSTextField()
    private let sizeLabel = NSTextField()
    private let iconView = NSImageView()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        // 设置图标
        iconView.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Audio File")
        iconView.translatesAutoresizingMaskIntoConstraints = false
        
        // 设置标签
        setupLabel(nameLabel, font: .systemFont(ofSize: 14, weight: .medium))
        setupLabel(dateLabel, font: .systemFont(ofSize: 12))
        setupLabel(durationLabel, font: .systemFont(ofSize: 12))
        setupLabel(sizeLabel, font: .systemFont(ofSize: 12))
        
        // 添加子视图
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(dateLabel)
        addSubview(durationLabel)
        addSubview(sizeLabel)
        
        // 设置约束
        NSLayoutConstraint.activate([
            // 图标
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            
            // 文件名
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            
            // 时长（从左边开始）
            durationLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            durationLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            
            // 大小（紧跟时长后面）
            sizeLabel.leadingAnchor.constraint(equalTo: durationLabel.trailingAnchor, constant: 16),
            sizeLabel.centerYAnchor.constraint(equalTo: durationLabel.centerYAnchor),
            
            // 日期（隐藏，不显示）
            dateLabel.widthAnchor.constraint(equalToConstant: 0),
            dateLabel.heightAnchor.constraint(equalToConstant: 0),
            
            // 高度
            heightAnchor.constraint(equalToConstant: 60)
        ])
    }
    
    private func setupLabel(_ label: NSTextField, font: NSFont) {
        label.isBordered = false
        label.isEditable = false
        label.backgroundColor = .clear
        label.font = font
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
    }
    
    func configure(with file: RecordedFileInfo) {
        nameLabel.stringValue = file.name
        // 第二排只显示时长和大小，不显示日期
        dateLabel.stringValue = ""
        durationLabel.stringValue = "时长: \(file.formattedDuration)"
        sizeLabel.stringValue = "大小: \(file.formattedSize)"
    }
}
