//
// ChatViewController.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//


import UIKit
import Shared
import Martin
import MartinOMEMO
import Combine

class ChatViewController : BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar {

    var chat: Chat {
        return conversation as! Chat;
    }
    
    var titleView: ChatTitleView! {
        get {
            return (self.navigationItem.titleView as! ChatTitleView);
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func conversationTableViewDelegate() -> UITableViewDelegate? {
        return self;
    }
        
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(ChatViewController.showBuddyInfo));
        self.titleView.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);

        initializeSharing();
    }
    
    @objc func showBuddyInfo(_ button: Any) {
        let navigation = storyboard?.instantiateViewController(withIdentifier: "ContactViewNavigationController") as! UINavigationController;
        let contactView = navigation.visibleViewController as! ContactViewController;
        contactView.account = conversation.account;
        contactView.jid = conversation.jid;
        contactView.chat = self.chat;
        //contactView.showEncryption = true;
        navigation.title = self.navigationItem.title;
        navigation.modalPresentationStyle = .formSheet;
        self.present(navigation, animated: true, completion: nil);

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        if CallManager.isAvailable {
            var buttons: [UIBarButtonItem] = [];
            buttons.append(self.smallBarButtinItem(image: UIImage(named: "videoCall")!, action: #selector(self.videoCall)));
            buttons.append(self.smallBarButtinItem(image: UIImage(named: "audioCall")!, action: #selector(self.audioCall)));
            self.navigationItem.rightBarButtonItems = buttons;
        }

        conversation.context?.$state.map({ $0 == .connected() }).receive(on: DispatchQueue.main).assign(to: \.connected, on: self.titleView).store(in: &cancellables);
        conversation.displayNamePublisher.map({ $0 }).assign(to: \.name, on: self.titleView).store(in: &cancellables);
        conversation.statusPublisher.combineLatest(conversation.descriptionPublisher, chat.optionsPublisher).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (show, description, options) in
            self?.titleView.setStatus(show, description: description, encryption: options.encryption);
        }).store(in: &cancellables)        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        //NotificationCenter.default.removeObserver(self);
        cancellables.removeAll();
        super.viewDidDisappear(animated);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        guard let item = dataSource.getItem(at: indexPath.row) else {
            return;
        }

        let alert = UIAlertController(title: NSLocalizedString("Details", comment: "alert title"), message: item.state.errorMessage ?? NSLocalizedString("Unknown error occurred", comment: "alert body"), preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("Resend", comment: "button label"), style: .default, handler: {(action) in
            switch item.payload {
            case .message(let message, _):
                self.chat.sendMessage(text: message, correctedMessageOriginId: nil);
                DBChatHistoryStore.instance.remove(item: item);
            case .attachment(let url, let appendix):
                let oldLocalFile = DownloadStore.instance.url(for: "\(item.id)");
                self.chat.sendAttachment(url: url, appendix: appendix, originalUrl: oldLocalFile, completionHandler: {
                    DBChatHistoryStore.instance.remove(item: item);
                });
            default:
                break;
            }
        }));
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        self.present(alert, animated: true, completion: nil);
    }
     
    override func canExecuteContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ConversationEntry, at indexPath: IndexPath) -> Bool {
        switch action {
        case .retract:
            return item.state.direction == .outgoing && XmppService.instance.getClient(for: item.conversation.account)?.isConnected ?? false;
        case .report:
            return item.state.direction == .incoming && XmppService.instance.getClient(for: item.conversation.account)?.module(.blockingCommand).isReportingSupported ?? false;
        default:
            return super.canExecuteContext(action: action, forItem: item, at: indexPath);
        }
    }
    
    override func executeContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ConversationEntry, at indexPath: IndexPath) {
        switch action {
        case .retract:
            guard item.state.direction == .outgoing else {
                return;
            }
            
            chat.retract(entry: item)
        default:
            super.executeContext(action: action, forItem: item, at: indexPath);
        }
    }
    
    fileprivate func smallBarButtinItem(image: UIImage, action: Selector) -> UIBarButtonItem {
        let btn = UIButton(type: .custom);
        btn.setImage(image, for: .normal);
        btn.addTarget(self, action: action, for: .touchUpInside);
        btn.frame = CGRect(x: 0, y: 0, width: 30, height: 30);
        return UIBarButtonItem(customView: btn);
    }
    
    @objc func audioCall() {
        VideoCallController.call(jid: self.conversation.jid, from: self.conversation.account, media: [.audio], sender: self);
    }
    
    @objc func videoCall() {
        VideoCallController.call(jid: self.conversation.jid, from: self.conversation.account, media: [.audio, .video], sender: self);
    }
    
    @IBAction func sendClicked(_ sender: UIButton) {
        sendMessage();
    }
    
    override func sendMessage() {
        guard let text = messageText, !text.isEmpty else {
            return;
        }
        
        chat.sendMessage(text: text, correctedMessageOriginId: self.correctedMessageOriginId)
        DispatchQueue.main.async {
            self.messageText = nil;
        }
    }
    
    
    override func sendAttachment(originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (() -> Void)?) {
        chat.sendAttachment(url: uploadedUrl, appendix: appendix, originalUrl: originalUrl, completionHandler: completionHandler);
    }
        
}

class BaseConversationTitleView: UIView {
    
    @IBOutlet var nameView: UILabel!;
    @IBOutlet var statusView: UILabel!;
    
    override var intrinsicContentSize: CGSize {
        return UIView.layoutFittingExpandedSize
    }
}

class ChatTitleView: BaseConversationTitleView {

    var encryption: ChatEncryption? = nil;
    
    var name: String? {
        get {
            return nameView.text;
        }
        set {
            nameView.text = newValue;
        }
    }
    
    var connected: Bool = false {
        didSet {
            guard oldValue != connected else {
                return;
            }
            refresh();
        }
    }
    
//    var status: Presence? {
//        didSet {
//            self.refresh();
//        }
//    }

    private var statusShow: Presence.Show? = nil;
    private var statusDescription: String? = nil;
    
    func setStatus(_ show: Presence.Show?, description: String?, encryption: ChatEncryption?) {
        statusShow = show;
        statusDescription = description;
        self.encryption = encryption;
        refresh();
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview();
        if let superview = self.superview {
            NSLayoutConstraint.activate([ self.widthAnchor.constraint(lessThanOrEqualTo: superview.widthAnchor, multiplier: 0.6)]);
        }
    }
    
//    func reload(for account: BareJID, with jid: BareJID) {
//        if let rosterModule: RosterModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(RosterModule.ID) {
//            self.name = rosterModule.rosterStore.get(for: JID(jid))?.name ?? jid.stringValue;
//        } else {
//            self.name = jid.stringValue;
//        }
//        self.encryption = (DBChatStore.instance.getChat(for: account, with: jid) as? DBChat)?.options.encryption;
//    }
    
    fileprivate func refresh() {
        DispatchQueue.main.async {
            let encryption = self.encryption ?? Settings.messageEncryption;
            if self.connected {
                let statusIcon = NSTextAttachment();
                statusIcon.image = AvatarStatusView.getStatusImage(self.statusShow);
                let height = self.statusView.font.pointSize;
                statusIcon.bounds = CGRect(x: 0, y: -2, width: height, height: height);
                var desc = self.statusDescription;
                if desc == nil {
                    let show = self.statusShow;
                    if show == nil {
                        desc = NSLocalizedString("Offline", comment: "user status");
                    } else {
                        switch(show!) {
                        case .online:
                            desc = NSLocalizedString("Online", comment: "user status");
                        case .chat:
                            desc = NSLocalizedString("Free for chat", comment: "user status");
                        case .away:
                            desc = NSLocalizedString("Be right back", comment: "user status");
                        case .xa:
                            desc = NSLocalizedString("Away", comment: "user status");
                        case .dnd:
                            desc = NSLocalizedString("Do not disturb", comment: "user status");
                        }
                    }
                }
                let statusText = NSMutableAttributedString(string: encryption == .none ? "" : "\u{1F512} ");
                statusText.append(NSAttributedString(attachment: statusIcon));
                statusText.append(NSAttributedString(string: desc!));
                self.statusView.attributedText = statusText;
            } else {
                switch encryption {
                case .omemo:
                    self.statusView.text = "\u{1F512} \u{26A0} \(NSLocalizedString("Not connected", comment: "channel status label"))!";
                case .none:
                    self.statusView.text = "\u{26A0} \(NSLocalizedString("Not connected", comment: "channel status label"))!";
                }
            }            
        }
    }
}
