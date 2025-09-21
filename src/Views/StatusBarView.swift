import Cocoa
import Foundation

// MARK: - StatusBarView
/// 状态栏视图 - 负责显示应用程序状态信息
class StatusBarView: NSView {
    
    // MARK: - UI Components
    private let statusLabel = NSTextField()
    
    // MARK: - Properties
    private var currentStatus: String = "准备就绪"
    
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
        layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        
        setupStatusLabel()
        setupConstraints()
    }
    
    private func setupStatusLabel() {
        statusLabel.stringValue = currentStatus
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.isBordered = false
        statusLabel.isEditable = false
        statusLabel.backgroundColor = .clear
        statusLabel.alignment = .left
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12)
        ])
    }
    
    // MARK: - Public Methods
    func updateStatus(_ status: String) {
        currentStatus = status
        statusLabel.stringValue = status
    }
    
    func getCurrentStatus() -> String {
        return currentStatus
    }
}
