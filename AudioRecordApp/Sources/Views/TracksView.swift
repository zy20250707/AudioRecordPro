import Cocoa
import Foundation

// TrackInfo 已移动到 AudioRecordKit/Sources/API/Types.swift

// MARK: - Delegate Protocol
protocol TracksViewDelegate: AnyObject {
    func tracksViewDidUpdateTracks(_ view: TracksView, tracks: [TrackInfo])
}

// MARK: - TracksView
/// 轨道视图 - 负责显示和管理音频轨道
class TracksView: NSView {
    
    // MARK: - UI Components
    private let tracksStack = NSStackView()
    
    // MARK: - Properties
    weak var delegate: TracksViewDelegate?
    private var currentTracks: [TrackInfo] = []
    
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
        layer?.backgroundColor = NSColor.white.cgColor
        
        setupTracksStack()
    }
    
    private func setupTracksStack() {
        tracksStack.orientation = .vertical
        tracksStack.spacing = 12
        tracksStack.alignment = .leading
        tracksStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tracksStack)
        
        NSLayoutConstraint.activate([
            tracksStack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            tracksStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            tracksStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            tracksStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])
    }
    
    // MARK: - Public Methods
    func updateTracks(_ tracks: [TrackInfo]) {
        currentTracks = tracks
        clearTracks()
        
        for track in tracks {
            addTrackRow(track)
        }
        
        delegate?.tracksViewDidUpdateTracks(self, tracks: tracks)
    }
    
    func updateLevel(_ level: Float) {
        // 将电平分发到所有轨道中的 LevelMeterView
        for row in tracksStack.arrangedSubviews {
            for subview in row.subviews {
                if let meter = subview as? LevelMeterView {
                    meter.updateLevel(level)
                }
            }
        }
    }
    
    func clearTracks() {
        // 清空现有轨道
        for view in tracksStack.arrangedSubviews {
            tracksStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }
    
    // MARK: - Private Methods
    private func addTrackRow(_ track: TrackInfo) {
        let trackView = NSView()
        trackView.translatesAutoresizingMaskIntoConstraints = false
        
        // 顶部头部区域（图标 + 标题）
        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        
        // 图标：优先使用应用图标，否则使用 Emoji
        let iconView: NSView
        if let appIcon = track.appIcon {
            // 使用应用图标（NSImageView）
            let imageView = NSImageView()
            imageView.image = appIcon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            iconView = imageView
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(equalToConstant: 24),
                imageView.heightAnchor.constraint(equalToConstant: 24)
            ])
        } else {
            // 使用 Emoji 图标（NSTextField）
            let iconLabel = NSTextField()
            iconLabel.stringValue = track.icon
            iconLabel.isBordered = false
            iconLabel.isEditable = false
            iconLabel.backgroundColor = .clear
            iconLabel.font = NSFont.systemFont(ofSize: 24)
            iconLabel.translatesAutoresizingMaskIntoConstraints = false
            iconView = iconLabel
        }
        
        let titleLabel = NSTextField()
        titleLabel.stringValue = track.title
        titleLabel.isBordered = false
        titleLabel.isEditable = false
        titleLabel.backgroundColor = .clear
        titleLabel.font = NSFont.systemFont(ofSize: 18)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(iconView)
        headerView.addSubview(titleLabel)

        // 电平表在下方占满宽度
        let levelMeter = LevelMeterView()
        levelMeter.translatesAutoresizingMaskIntoConstraints = false

        trackView.addSubview(headerView)
        trackView.addSubview(levelMeter)

        NSLayoutConstraint.activate([
            trackView.heightAnchor.constraint(equalToConstant: 140),

            // Header 布局
            headerView.topAnchor.constraint(equalTo: trackView.topAnchor, constant: 12),
            headerView.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 16),
            headerView.trailingAnchor.constraint(lessThanOrEqualTo: trackView.trailingAnchor, constant: -16),
            headerView.heightAnchor.constraint(equalToConstant: 28),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor),

            // LevelMeter 在下方
            levelMeter.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 10),
            levelMeter.leadingAnchor.constraint(equalTo: trackView.leadingAnchor, constant: 16),
            levelMeter.trailingAnchor.constraint(equalTo: trackView.trailingAnchor, constant: -16),
            levelMeter.bottomAnchor.constraint(equalTo: trackView.bottomAnchor, constant: -12),
            levelMeter.heightAnchor.constraint(equalToConstant: 96)
        ])
        
        tracksStack.addArrangedSubview(trackView)
    }
}

// MARK: - Convenience Extensions
extension TracksView {
    /// 根据侧边栏选择创建轨道信息
    static func createTracksFromSelection(
        systemSelected: Bool,
        microphoneSelected: Bool,
        selectedProcesses: [AudioProcessInfo]
    ) -> [TrackInfo] {
        var tracks: [TrackInfo] = []
        
        if systemSelected {
            tracks.append(TrackInfo(icon: "🔊", title: "系统音频输出", isActive: true))
        }
        
        if microphoneSelected {
            tracks.append(TrackInfo(icon: "🎤", title: "麦克风", isActive: true))
        }
        
        for process in selectedProcesses {
            tracks.append(TrackInfo(icon: "📱", title: process.name, isActive: true))
        }
        
        return tracks
    }
}
