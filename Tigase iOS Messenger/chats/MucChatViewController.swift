//
// MucChatViewController.swift
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

class MucChatViewController: BaseChatViewController, CachedViewControllerProtocol, UITableViewDataSource, EventHandler {

    var titleView: MucTitleView!;
    var room: Room?;
    
    let log: Logger = Logger();
    var scrollToIndexPath: NSIndexPath? = nil;

    var dataSource: MucChatDataSource!;
    var cachedDataSource: CachedViewDataSourceProtocol {
        return dataSource as CachedViewDataSourceProtocol;
    }

    override func viewDidLoad() {
        dataSource = MucChatDataSource(controller: self);
        scrollDelegate = self;
        super.viewDidLoad()
        initialize();
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        let mucModule: MucModule? = xmppService.getClient(account)?.modulesManager?.getModule(MucModule.ID);
        room = mucModule?.roomsManager.get(jid.bareJid);

        tableView.dataSource = self;
        
        let navBarHeight = self.navigationController!.navigationBar.frame.size.height;
        let width = CGFloat(220);
        
        titleView = MucTitleView(width: width, height: navBarHeight);
        titleView.name = navigationItem.title;
        
        self.navigationItem.titleView = titleView;
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated);
        xmppService.registerEventHandler(self, events: MucModule.YouJoinedEvent.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MucChatViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MucChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        refreshRoomInfo(room!);
    }
    
    override func viewDidDisappear(animated: Bool) {
        xmppService.unregisterEventHandler(self, events: MucModule.YouJoinedEvent.TYPE, MucModule.JoinRequestedEvent.TYPE, MucModule.RoomClosedEvent.TYPE);
        NSNotificationCenter.defaultCenter().removeObserver(self);
        super.viewDidDisappear(animated);
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
        let item: MucChatViewItem = dataSource.getItem(indexPath);
        
        let incoming = item.nickname != self.room?.nickname;
        let id = incoming ? "MucChatTableViewCellIncoming" : "MucChatTableViewCellOutgoing"
        
        let cell = tableView.dequeueReusableCellWithIdentifier(id, forIndexPath: indexPath) as! MucChatTableViewCell;
        cell.transform = dataSource.inverted ? CGAffineTransformMake(1, 0, 0, -1, 0, 0) : CGAffineTransformIdentity;
        cell.nicknameLabel?.text = item.nickname;
        if item.authorJid != nil {
            cell.avatarView?.image = self.xmppService.avatarManager.getAvatar(item.authorJid!, account: self.account);
        } else {
            cell.avatarView?.image = self.xmppService.avatarManager.defaultAvatar;
        }
        cell.setMessageText(item.data);
        cell.setTimestamp(item.timestamp);
        return cell;
    }

    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showOccupants" {
            if let navigation = segue.destinationViewController as? UINavigationController {
                if let occupantsController = navigation.visibleViewController as? MucChatOccupantsTableViewController {
                    occupantsController.room = room;
                    occupantsController.account = account;
                }
            }
        }
    }
    
    func newMessage(notification: NSNotification) {
        guard ((notification.userInfo?["account"] as? BareJID) == account) && ((notification.userInfo?["sender"] as? BareJID) == jid.bareJid) else {
            return;
        }
        
        dispatch_sync(dispatch_get_main_queue()) {
            self.newItemAdded();
        }
        xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
    }
    
    func avatarChanged(notification: NSNotification) {
        // TODO: adjust this to make it work properly with MUC
        guard ((notification.userInfo?["jid"] as? BareJID) == jid.bareJid) else {
            return;
        }
        dispatch_async(dispatch_get_main_queue()) {
            if let indexPaths = self.tableView.indexPathsForVisibleRows {
                self.tableView.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .None);
            }
        }
    }
        
    @IBAction func sendClicked(sender: UIButton) {
        let text = messageField.text;
        guard !(text?.isEmpty != false) else {
            return;
        }

        guard room?.state == .joined else {
            let alert: UIAlertController?  = UIAlertController.init(title: "Warning", message: "You are not connected to room.\nPlease wait reconnection to room", preferredStyle: .Alert);
            alert?.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil));
            self.presentViewController(alert!, animated: true, completion: nil);
            return;
        }
        
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
            self.room!.sendMessage(text);
        }
        messageField.text = nil;
    }
    
    func handleEvent(event: Event) {
        switch event {
        case let e as MucModule.JoinRequestedEvent:
            dispatch_async(dispatch_get_main_queue()) {
                self.refreshRoomInfo(e.room);
            }
        case let e as MucModule.YouJoinedEvent:
            dispatch_async(dispatch_get_main_queue()) {
                self.refreshRoomInfo(e.room);
            }
        case let e as MucModule.RoomClosedEvent:
            dispatch_async(dispatch_get_main_queue()) {
                self.refreshRoomInfo(e.room);
            }
        default:
            break;
        }
    }
    
    func refreshRoomInfo(room: Room) {
        titleView.state = room.state;
    }
    
    class MucChatDataSource: CachedViewDataSource<MucChatViewItem> {
        
        private let getMessagesStmt: DBStatement!;
        
        weak var controller: MucChatViewController?;
        
        init(controller: MucChatViewController) {
            self.controller = controller;
            self.getMessagesStmt = controller.xmppService.dbChatHistoryStore.getMessagesStatementForAccountAndJid();
        }
        
        override func getItemsCount() -> Int {
            return controller!.xmppService.dbChatHistoryStore.countMessages(controller!.account, jid: controller!.jid.bareJid);
        }
        
        override func loadData(offset: Int, limit: Int, forEveryItem: (MucChatViewItem)->Void) {
            controller!.xmppService.dbChatHistoryStore.forEachMessage(getMessagesStmt, account: controller!.account, jid: controller!.jid.bareJid, limit: limit, offset: offset, forEach: { (cursor)-> Void in
                forEveryItem(MucChatViewItem(cursor: cursor));
            });
        }
    }
    
    public class MucChatViewItem {
        let nickname: String?;
        let timestamp: NSDate!;
        let data: String?;
        let authorJid: BareJID?;
        
        init(cursor: DBCursor) {
            nickname = cursor["author_nickname"];
            timestamp = cursor["timestamp"]!;
            data = cursor["data"];
            authorJid = cursor["author_jid"];
        }
        
    }
    
    class MucTitleView: UIView {
        
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
        
        var state: Room.State = Room.State.not_joined {
            didSet {
                let statusIcon = NSTextAttachment();
                
                var show: Presence.Show?;
                var desc = "Offline";
                switch state {
                case .joined:
                    show = Presence.Show.online;
                    desc = "Online";
                case .requested:
                    show = Presence.Show.away;
                    desc = "Joining...";
                default:
                    break;
                }
                
                statusIcon.image = AvatarStatusView.getStatusImage(show);
                statusIcon.bounds = CGRectMake(0, -3, statusHeight, statusHeight);
                
                let statusText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: statusIcon));
                statusText.appendAttributedString(NSAttributedString(string: desc));
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



