import Cocoa
import Foundation

// MARK: - TabItem
struct TabItem {
    let id: String
    let title: String
    let icon: String?
    let view: NSView
    
    init(id: String, title: String, icon: String? = nil, view: NSView) {
        self.id = id
        self.title = title
        self.icon = icon
        self.view = view
    }
}

// MARK: - Delegate Protocol
protocol TabContainerViewDelegate: AnyObject {
    func tabContainerViewDidSelectTab(_ view: TabContainerView, tabId: String)
}

// MARK: - TabContainerView
/// Tab容器视图 - 管理多个Tab的切换
class TabContainerView: NSView {
    
    // MARK: - UI Components
    private let tabBarView = NSView()
    private let contentView = NSView()
    private var tabButtons: [String: NSButton] = [:]
    private var selectedTabId: String?
    
    // MARK: - Properties
    weak var delegate: TabContainerViewDelegate?
    private var tabs: [TabItem] = []
    
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
        
        setupTabBar()
        setupContentView()
        setupConstraints()
    }
    
    private func setupTabBar() {
        tabBarView.wantsLayer = true
        tabBarView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        tabBarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabBarView)
    }
    
    private func setupContentView() {
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Tab栏约束
            tabBarView.topAnchor.constraint(equalTo: topAnchor),
            tabBarView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBarView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBarView.heightAnchor.constraint(equalToConstant: 44),
            
            // 内容视图约束
            contentView.topAnchor.constraint(equalTo: tabBarView.bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Public Methods
    
    /// 添加Tab
    func addTab(_ tab: TabItem) {
        tabs.append(tab)
        createTabButton(for: tab)
        
        // 如果是第一个Tab，自动选中
        if selectedTabId == nil {
            selectTab(tab.id)
        }
    }
    
    /// 选择Tab
    func selectTab(_ tabId: String) {
        guard let tab = tabs.first(where: { $0.id == tabId }) else { return }
        
        // 更新按钮状态
        updateTabButtonStates(selectedId: tabId)
        
        // 更新内容视图
        updateContentView(with: tab)
        
        selectedTabId = tabId
        delegate?.tabContainerViewDidSelectTab(self, tabId: tabId)
    }
    
    /// 获取当前选中的Tab ID
    func getSelectedTabId() -> String? {
        return selectedTabId
    }
    
    /// 获取指定Tab的视图
    func getTabView(_ tabId: String) -> NSView? {
        return tabs.first(where: { $0.id == tabId })?.view
    }
    
    // MARK: - Private Methods
    
    private func createTabButton(for tab: TabItem) {
        let button = NSButton()
        button.title = tab.title
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        
        // 设置字体
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        
        // 设置图标（如果有）
        if let icon = tab.icon {
            button.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            button.imagePosition = .imageLeft
            button.imageHugsTitle = true
        }
        
        // 设置点击事件
        button.target = self
        button.action = #selector(tabButtonClicked(_:))
        button.tag = tabs.count - 1
        
        tabButtons[tab.id] = button
        tabBarView.addSubview(button)
        
        // 设置按钮约束
        setupTabButtonConstraints(button, at: tabs.count - 1)
    }
    
    private func setupTabButtonConstraints(_ button: NSButton, at index: Int) {
        NSLayoutConstraint.activate([
            button.centerYAnchor.constraint(equalTo: tabBarView.centerYAnchor),
            button.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        if index == 0 {
            // 第一个按钮
            button.leadingAnchor.constraint(equalTo: tabBarView.leadingAnchor, constant: 16).isActive = true
        } else {
            // 后续按钮
            let previousButton = tabButtons[tabs[index - 1].id]
            button.leadingAnchor.constraint(equalTo: previousButton!.trailingAnchor, constant: 8).isActive = true
        }
        
        // 最后一个按钮的右边距
        if index == tabs.count - 1 {
            button.trailingAnchor.constraint(lessThanOrEqualTo: tabBarView.trailingAnchor, constant: -16).isActive = true
        }
    }
    
    private func updateTabButtonStates(selectedId: String) {
        for (tabId, button) in tabButtons {
            if tabId == selectedId {
                // 选中状态
                button.layer?.backgroundColor = NSColor.selectedControlColor.cgColor
                button.contentTintColor = NSColor.selectedControlTextColor
                button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            } else {
                // 未选中状态
                button.layer?.backgroundColor = NSColor.clear.cgColor
                button.contentTintColor = NSColor.labelColor
                button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            }
        }
    }
    
    private func updateContentView(with tab: TabItem) {
        // 移除当前内容视图的所有子视图
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }
        
        // 添加新的内容视图
        tab.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tab.view)
        
        NSLayoutConstraint.activate([
            tab.view.topAnchor.constraint(equalTo: contentView.topAnchor),
            tab.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tab.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tab.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
    
    @objc private func tabButtonClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0 && index < tabs.count else { return }
        
        let tab = tabs[index]
        selectTab(tab.id)
    }
}
