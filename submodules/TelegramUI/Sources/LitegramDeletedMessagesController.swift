import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import Litegram

public final class LitegramDeletedMessagesController: ViewController {
    private let context: AccountContext
    private var presentationData: PresentationData
    
    private var scrollNode: ASScrollNode?
    private var emptyNode: ASTextNode?
    private var cellNodes: [(container: ASDisplayNode, author: ASTextNode, text: ASTextNode, date: ASTextNode, sep: ASDisplayNode)] = []
    
    private var messages: [LitegramDeletedMessage] = []
    private var observer: NSObjectProtocol?
    private var lastLayout: ContainerViewLayout?
    
    private var toggleNode: ASDisplayNode?
    private var toggleTitleNode: ASTextNode?
    private var toggleSwitch: UISwitch?
    private var toggleSepNode: ASDisplayNode?
    
    public init(context: AccountContext) {
        self.context = context
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        
        self.title = "Удалённые сообщения"
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Очистить", style: .plain, target: self, action: #selector(clearTapped))
        
        self.messages = LitegramDeletedMessageStore.shared.allMessages()
        
        self.observer = NotificationCenter.default.addObserver(forName: .litegramDeletedMessagesUpdated, object: nil, queue: .main) { [weak self] _ in
            self?.reloadData()
        }
    }
    
    required init(coder: NSCoder) { fatalError() }
    
    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
    
    override public func loadDisplayNode() {
        self.displayNode = ASDisplayNode()
        self.displayNode.backgroundColor = presentationData.theme.list.blocksBackgroundColor
        
        let scroll = ASScrollNode()
        scroll.view.alwaysBounceVertical = true
        self.displayNode.addSubnode(scroll)
        self.scrollNode = scroll
        
        buildToggle()
        buildCells()
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        self.lastLayout = layout
        
        let width = layout.size.width
        let safeLeft = layout.safeInsets.left
        let contentWidth = width - safeLeft * 2
        let navBarHeight = self.navigationLayout(layout: layout).navigationFrame.maxY
        
        scrollNode?.frame = CGRect(x: 0, y: navBarHeight, width: width, height: layout.size.height - navBarHeight)
        
        var y: CGFloat = 16
        
        if let toggle = toggleNode {
            let h: CGFloat = 52
            toggle.frame = CGRect(x: safeLeft + 16, y: y, width: contentWidth - 32, height: h)
            toggleTitleNode?.frame = CGRect(x: 16, y: 0, width: contentWidth - 100, height: h)
            toggleSwitch?.frame = CGRect(x: contentWidth - 32 - 51, y: (h - 31) / 2, width: 51, height: 31)
            toggleSepNode?.frame = CGRect(x: 16, y: h - 0.5, width: contentWidth - 64, height: 0.5)
            y += h + 16
        }
        
        if messages.isEmpty {
            emptyNode?.frame = CGRect(x: safeLeft, y: y + 60, width: contentWidth, height: 40)
        }
        
        for cell in cellNodes {
            let textWidth = contentWidth - 32 - 32
            
            let authorSize = cell.author.calculateSizeThatFits(CGSize(width: textWidth, height: 20))
            let dateSize = cell.date.calculateSizeThatFits(CGSize(width: 120, height: 16))
            let textSize = cell.text.calculateSizeThatFits(CGSize(width: textWidth, height: 200))
            let cellH = max(66, 12 + authorSize.height + 4 + textSize.height + 12)
            
            cell.container.frame = CGRect(x: safeLeft + 16, y: y, width: contentWidth - 32, height: cellH)
            cell.author.frame = CGRect(x: 16, y: 12, width: textWidth - dateSize.width - 8, height: authorSize.height)
            cell.date.frame = CGRect(x: contentWidth - 32 - 16 - dateSize.width, y: 14, width: dateSize.width, height: dateSize.height)
            cell.text.frame = CGRect(x: 16, y: 12 + authorSize.height + 4, width: textWidth, height: textSize.height)
            cell.sep.frame = CGRect(x: 16, y: cellH - 0.5, width: contentWidth - 64, height: 0.5)
            
            y += cellH
        }
        
        scrollNode?.view.contentSize = CGSize(width: width, height: y + 32 + layout.intrinsicInsets.bottom)
    }
    
    private func buildToggle() {
        let theme = presentationData.theme
        
        let container = ASDisplayNode()
        container.backgroundColor = theme.list.itemBlocksBackgroundColor
        container.cornerRadius = 12
        scrollNode?.addSubnode(container)
        self.toggleNode = container
        
        let title = ASTextNode()
        title.attributedText = NSAttributedString(
            string: "Сохранять удалённые",
            attributes: [
                .font: UIFont.systemFont(ofSize: 17),
                .foregroundColor: theme.list.itemPrimaryTextColor
            ]
        )
        container.addSubnode(title)
        self.toggleTitleNode = title
        
        let sw = UISwitch()
        sw.isOn = LitegramConfig.isSaveDeletedMessagesEnabled
        sw.onTintColor = theme.list.itemAccentColor
        sw.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        container.view.addSubview(sw)
        self.toggleSwitch = sw
        
        let sep = ASDisplayNode()
        sep.backgroundColor = theme.list.itemBlocksSeparatorColor
        container.addSubnode(sep)
        self.toggleSepNode = sep
    }
    
    private func buildCells() {
        for cell in cellNodes {
            cell.container.removeFromSupernode()
        }
        cellNodes.removeAll()
        emptyNode?.removeFromSupernode()
        emptyNode = nil
        
        let theme = presentationData.theme
        
        if messages.isEmpty {
            let empty = ASTextNode()
            empty.attributedText = NSAttributedString(
                string: "Пока нет удалённых сообщений",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15),
                    .foregroundColor: theme.list.itemSecondaryTextColor,
                    .paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .center; return p }()
                ]
            )
            scrollNode?.addSubnode(empty)
            self.emptyNode = empty
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        for msg in messages {
            let container = ASDisplayNode()
            container.backgroundColor = theme.list.itemBlocksBackgroundColor
            container.cornerRadius = 0
            
            let author = ASTextNode()
            author.maximumNumberOfLines = 1
            author.attributedText = NSAttributedString(
                string: msg.authorName ?? "Неизвестный",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
                    .foregroundColor: theme.list.itemAccentColor
                ]
            )
            container.addSubnode(author)
            
            let text = ASTextNode()
            text.maximumNumberOfLines = 4
            text.attributedText = NSAttributedString(
                string: msg.displayText,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15),
                    .foregroundColor: theme.list.itemPrimaryTextColor
                ]
            )
            container.addSubnode(text)
            
            let date = ASTextNode()
            date.attributedText = NSAttributedString(
                string: formatter.string(from: msg.date),
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: theme.list.itemSecondaryTextColor
                ]
            )
            container.addSubnode(date)
            
            let sep = ASDisplayNode()
            sep.backgroundColor = theme.list.itemBlocksSeparatorColor
            container.addSubnode(sep)
            
            scrollNode?.addSubnode(container)
            cellNodes.append((container: container, author: author, text: text, date: date, sep: sep))
        }
        
        if let first = cellNodes.first {
            first.container.clipsToBounds = true
            first.container.cornerRadius = 12
            if #available(iOS 11.0, *) {
                first.container.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            }
        }
        if let last = cellNodes.last {
            last.container.clipsToBounds = true
            last.container.cornerRadius = 12
            if #available(iOS 11.0, *) {
                last.container.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
            last.sep.isHidden = true
        }
    }
    
    private func reloadData() {
        messages = LitegramDeletedMessageStore.shared.allMessages()
        buildCells()
        if let layout = self.lastLayout {
            containerLayoutUpdated(layout, transition: .immediate)
        }
    }
    
    @objc private func clearTapped() {
        LitegramDeletedMessageStore.shared.clearAll()
    }
    
    @objc private func toggleChanged() {
        LitegramConfig.isSaveDeletedMessagesEnabled = toggleSwitch?.isOn ?? true
    }
}
