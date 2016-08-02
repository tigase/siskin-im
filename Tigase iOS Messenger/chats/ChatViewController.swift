//
// ChatViewController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//


import UIKit
import TigaseSwift

class ChatViewController : BaseChatViewController, UITableViewDataSource, EventHandler, CachedViewControllerProtocol {
    
    var titleView: ChatTitleView!;
    
    let log: Logger = Logger();
    var scrollToIndexPath: NSIndexPath? = nil;
    
    var dataSource: ChatDataSource!;
    var cachedDataSource: CachedViewDataSourceProtocol {
        return dataSource as CachedViewDataSourceProtocol;
    }
    
    override func viewDidLoad() {
        dataSource = ChatDataSource(controller: self);
        scrollDelegate = self;
        super.viewDidLoad()
        self.initialize();
        tableView.dataSource = self;
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        
        let navBarHeight = self.navigationController!.navigationBar.frame.size.height;
        let width = CGFloat(220);

        titleView = ChatTitleView(width: width, height: navBarHeight);
        titleView.name = navigationItem.title;
        
        let buddyBtn = UIButton(type: .System);
        buddyBtn.frame = CGRectMake(0,0, width, navBarHeight);
        buddyBtn.addSubview(titleView);
        
        buddyBtn.addTarget(self, action: #selector(ChatViewController.showBuddyInfo), forControlEvents: .TouchDown);
        self.navigationItem.titleView = buddyBtn;
    }
    
    func showBuddyInfo(button: UIButton) {
        print("open buddy info!");
        let navigation = storyboard?.instantiateViewControllerWithIdentifier("ContactViewNavigationController") as! UINavigationController;
        let contactView = navigation.visibleViewController as! ContactViewController;
        contactView.account = account;
        contactView.jid = jid.bareJid;
        navigation.title = self.navigationItem.title;
        self.showDetailViewController(navigation, sender: self);

    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        
        xmppService.registerEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE);
        
        let presenceModule: PresenceModule? = xmppService.getClient(account)?.modulesManager.getModule(PresenceModule.ID);
        titleView.status = presenceModule?.presenceStore.getBestPresence(jid.bareJid);
    }
    
    override func viewDidDisappear(animated: Bool) {
        NSNotificationCenter.defaultCenter().removeObserver(self);
        super.viewDidDisappear(animated);
        
        xmppService.unregisterEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1;
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return dataSource.numberOfMessages;
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let item = dataSource.getItem(indexPath);
        let incoming = (item.state % 2) == 0;
        let id = incoming ? "ChatTableViewCellIncoming" : "ChatTableViewCellOutgoing"
        let cell:ChatTableViewCell = tableView.dequeueReusableCellWithIdentifier(id, forIndexPath: indexPath) as! ChatTableViewCell;
        cell.transform = cachedDataSource.inverted ? CGAffineTransformMake(1, 0, 0, -1, 0, 0) : CGAffineTransformIdentity;
        cell.avatarView?.image = self.xmppService.avatarManager.getAvatar(self.jid.bareJid, account: self.account);
        cell.setMessageText(item.data);
        cell.setTimestamp(item.timestamp);
        cell.setNeedsUpdateConstraints();
        cell.updateConstraintsIfNeeded();
        return cell;
    }
    
    class ChatViewItem {
        let state: Int;
        let data: String?;
        let timestamp: NSDate;
        
        init(cursor: DBCursor) {
            state = cursor["state"]!;
            data = cursor["data"];
            timestamp = cursor["timestamp"]!;
        }
        
    }
    
    func handleEvent(event: Event) {
        switch event {
        case let cpc as PresenceModule.ContactPresenceChanged:
            guard cpc.presence.from?.bareJid == self.jid.bareJid && cpc.sessionObject.userBareJid == account else {
                return;
            }
            
            dispatch_async(dispatch_get_main_queue()) {
                self.titleView.status = cpc.presence;
            }
        default:
            break;
        }
    }
    
    func newMessage(notification: NSNotification) {
        guard ((notification.userInfo?["account"] as? BareJID) == account) && ((notification.userInfo?["sender"] as? BareJID) == jid.bareJid) else {
            return;
        }
        
        dispatch_sync(dispatch_get_main_queue()) {
            self.newItemAdded();
        }

        self.xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
    }
    
    func avatarChanged(notification: NSNotification) {
        guard ((notification.userInfo?["jid"] as? BareJID) == jid.bareJid) else {
            return;
        }
        if let indexPaths = tableView.indexPathsForVisibleRows {
            tableView.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .None);
        }
    }
    
    @IBAction func sendClicked(sender: UIButton) {
        let text = messageField.text;
        guard !(text?.isEmpty != false) else {
            return;
        }
        
        let client = xmppService.getClient(account);
        if client != nil && client!.state == .connected {
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
                let messageModule:MessageModule? = client?.modulesManager.getModule(MessageModule.ID);
                if let chat = messageModule?.chatManager.getChat(self.jid, thread: nil) {
                    let msg = messageModule!.sendMessage(chat, body: text!);
                    self.xmppService.dbChatHistoryStore.appendMessage(self.account, message: msg);
                }
            }
            messageField.text = nil;
        } else {
            var alert: UIAlertController? = nil;
            if client == nil {
                alert = UIAlertController.init(title: "Warning", message: "Account is disabled.\nDo you want to enable account?", preferredStyle: .Alert);
                alert?.addAction(UIAlertAction(title: "No", style: .Cancel, handler: nil));
                alert?.addAction(UIAlertAction(title: "Yes", style: .Default, handler: {(alertAction) in
                    if let account = AccountManager.getAccount(self.account.stringValue) {
                        account.active = true;
                        AccountManager.updateAccount(account);
                    }
                }));
            } else if client?.state != .connected {
                alert = UIAlertController.init(title: "Warning", message: "Account is disconnected.\nPlease wait until account will reconnect", preferredStyle: .Alert);
                alert?.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil));
            }
            if alert != nil {
                self.presentViewController(alert!, animated: true, completion: nil);
            }
        }
    }
    
    class ChatDataSource: CachedViewDataSource<ChatViewItem> {
        
        private let getMessagesStmt: DBStatement!;
        
        weak var controller: ChatViewController?;
        
        init(controller: ChatViewController) {
            self.controller = controller;
            self.getMessagesStmt = controller.xmppService.dbChatHistoryStore.getMessagesStatementForAccountAndJid();
        }
        
        override func getItemsCount() -> Int {
            return controller!.xmppService.dbChatHistoryStore.countMessages(controller!.account, jid: controller!.jid.bareJid);
        }
        
        override func loadData(offset: Int, limit: Int, forEveryItem: (ChatViewItem)->Void) {
            controller!.xmppService.dbChatHistoryStore.forEachMessage(getMessagesStmt, account: controller!.account, jid: controller!.jid.bareJid, limit: limit, offset: offset, forEach: { (cursor)-> Void in
                forEveryItem(ChatViewItem(cursor: cursor));
            });
        }
    }
    
    class ChatTitleView: UIView {
        
        let nameView: UILabel!;
        let statusView: UILabel!;
        let statusHeight: CGFloat!;
        
        var name: String? {
            get {
                return nameView.text;
            }
            set {
                nameView.text = newValue;
            }
        }
        
        var status: Presence? {
            didSet {
                let statusIcon = NSTextAttachment();
                statusIcon.image = AvatarStatusView.getStatusImage(status?.show);
                statusIcon.bounds = CGRectMake(0, -3, statusHeight, statusHeight);
                var desc = status?.status;
                if desc == nil {
                    let show = status?.show;
                    if show == nil {
                        desc = "Offline";
                    } else {
                        switch(show!) {
                        case .online:
                            desc = "Online";
                        case .chat:
                            desc = "Free for chat";
                        case .away:
                            desc = "Be right back";
                        case .xa:
                            desc = "Away";
                        case .dnd:
                            desc = "Do not disturb";
                        }
                    }
                }
                let statusText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: statusIcon));
                statusText.appendAttributedString(NSAttributedString(string: desc!));
                statusView.attributedText = statusText;
            }
        }
        
        init(width: CGFloat, height: CGFloat) {
            let spacing = (height * 0.23) / 3;
            statusHeight = height * 0.32;
            nameView = UILabel(frame: CGRectMake(0, spacing, width, height * 0.48));
            statusView = UILabel(frame: CGRectMake(0, (height * 0.44) + (spacing * 2), width, statusHeight));
            super.init(frame: CGRectMake(0, 0, width, height));
            
            
            var font = nameView.font;
            font = font.fontWithSize(font.pointSize);
            nameView.font = font;
            nameView.textAlignment = .Center;
            nameView.adjustsFontSizeToFitWidth = true;
            
            font = statusView.font;
            font = font.fontWithSize(font.pointSize - 5);
            statusView.font = font;
            statusView.textAlignment = .Center;
            statusView.adjustsFontSizeToFitWidth = true;
            
            self.userInteractionEnabled = false;
            
            self.addSubview(nameView);
            self.addSubview(statusView);
        }
        
        required init?(coder aDecoder: NSCoder) {
            statusHeight = nil;
            statusView = nil;
            nameView = nil;
            super.init(coder: aDecoder);
        }
    }
}
