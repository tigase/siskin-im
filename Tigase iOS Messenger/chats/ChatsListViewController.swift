//
// ChatListViewController.swift
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

class ChatsListViewController: UITableViewController, EventHandler {
    var dbConnection:DBConnection {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.dbConnection;
    }
    var xmppService:XmppService {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    lazy var countChats:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) AS count FROM chats");
    lazy var getChat:DBStatement! = try? self.dbConnection.prepareStatement("SELECT jid, account, timestamp, thread_id, (SELECT data FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND item_type = 0 ORDER BY timestamp DESC LIMIT 1) AS last_message, (SELECT count(ch.id) FROM chat_history ch WHERE ch.account = c.account AND ch.jid = c.jid AND state = 2) as unread, (SELECT name FROM roster_items ri WHERE ri.account = c.account AND ri.jid = c.jid) as name FROM chats as c ORDER BY timestamp DESC LIMIT 1 OFFSET :offset");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.rowHeight = 66.0;//UITableViewAutomaticDimension;
        //tableView.estimatedRowHeight = 66.0;
        tableView.dataSource = self;
//        tableView.separatorStyle = .;
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatsListViewController.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        updateBadge();
    }
    
    override func viewWillAppear(animated: Bool) {
        xmppService.registerEventHandler(self, events: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE);
        tableView.reloadData();
        //(self.tabBarController as? CustomTabBarController)?.showTabBar();
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatsListViewController.newMessage), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }

    override func viewDidDisappear(animated: Bool) {
        super.viewDidDisappear(animated);
        xmppService.unregisterEventHandler(self, events: MessageModule.ChatCreatedEvent.TYPE, MessageModule.ChatClosedEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE);
        NSNotificationCenter.defaultCenter().removeObserver(self, name: AvatarManager.AVATAR_CHANGED, object: nil);
    }

    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self);
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return try! countChats.scalar() ?? 0;
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cellIdentifier = "ChatsListTableViewCell";
        let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier, forIndexPath: indexPath) as! ChatsListTableViewCell;
        
        let params:[String:Any?] = ["offset": indexPath.row];
        do {
            try getChat.query(params) { (cursor)->Void in
                let account = BareJID(cursor["account"] ?? "");
                let jidStr:String = cursor["jid"]!;
                let jid = BareJID(jidStr);
                let unread = cursor["unread"] ?? 0;
                cell.nameLabel.text = cursor["name"] ?? jidStr;
                cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.getAvatar(jid, account: account));
                let last_message:String? = cursor["last_message"];
                cell.lastMessageLabel.text = last_message == nil ? nil : ((unread > 0 ? "" : "\u{2713}") + last_message!);
                let formattedTS = self.formatTimestamp(cursor["timestamp"]!);
                cell.timestampLabel.text = formattedTS;
                let xmppClient = self.xmppService.getClient(account);
                let presenceModule:PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                let presence = presenceModule?.presenceStore.getBestPresence(jid);
                cell.avatarStatusView.setStatus(presence?.show);
            }
        } catch _ {
            cell.nameLabel.text = "DBError";
        }
        
        return cell;
    }
    
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        if (indexPath.section == 0) {
            return true;
        }
        return false;
    }
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == UITableViewCellEditingStyle.Delete {
            if indexPath.section == 0 {
                do {
                    let params:[String:Any?] = ["offset": indexPath.row];
                    try getChat.query(params) { (cursor)->Void in
                        let accountStr:String = cursor["account"]!;
                        let jidStr:String = cursor["jid"]!;
                        let account = BareJID(accountStr);
                        let jid = JID(jidStr);
                        let thread:String? = cursor["thread_id"];
                        
                        let xmppClient = self.xmppService.getClient(account);
                        let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                        if let chat = messageModule?.chatManager.getChat(jid, thread: thread) {
                            messageModule?.chatManager.close(chat);
                        }
                    }
                } catch _ {
                }
            }
        }
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showChatTableInDetailSegue" {
            let cell = sender as! ChatsListTableViewCell;
            if let indexPath = tableView.indexPathForCell(cell) {
                let navigation = segue.destinationViewController as! UINavigationController;
                let destination = navigation.visibleViewController as! ChatViewController;
                destination.hidesBottomBarWhenPushed = true;
                do {
                    let params:[String:Any?] = ["offset": indexPath.row];
                    try getChat.query(params) { (cursor)->Void in
                        let accountStr:String = cursor["account"]!;
                        let jidStr:String = cursor["jid"]!;
                        let account = BareJID(accountStr);
                        let jid = JID(jidStr);
                        
                        destination.account = account;
                        destination.jid = jid;
                        
                        self.tableView.deselectRowAtIndexPath(indexPath, animated: true);
                    }
                } catch _ {
                }
            }
        }
    }    

    func handleEvent(event: Event) {
        switch event {
        case is MessageModule.ChatCreatedEvent:
            tableView.beginUpdates();
            // we are adding rows always on top
            let index = NSIndexPath(forRow: 0, inSection: 0);
            tableView.insertRowsAtIndexPaths([index], withRowAnimation: UITableViewRowAnimation.Automatic);
            tableView.endUpdates();
            
            // if above is not working we can reload
            //tableView.reloadData();
        case is MessageModule.ChatClosedEvent:
            // we do not know position of chat which was closed
            tableView.reloadData();
        case is PresenceModule.ContactPresenceChanged:
            tableView.reloadData();
        default:
            break;
        }
    }
    
    func newMessage(notification:NSNotification) {
        if navigationController?.visibleViewController == self {
            tableView.reloadData();
        }
        let incoming:Bool = notification.userInfo?["incoming"] as? Bool ?? false;
        if incoming {
            updateBadge();
        }
    }
    
    func chatItemsUpdated(notification: NSNotification) {
        updateBadge();
    }
    
    func updateBadge() {
        let unreadChats = xmppService.dbChatHistoryStore.countUnreadChats();
        navigationController?.tabBarItem.badgeValue = unreadChats == 0 ? nil : String(unreadChats);
    }
    
    private static let todaysFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.dateStyle = .NoStyle;
        f.timeStyle = .ShortStyle;
        return f;
        })();
    private static let defaultFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.dateFormat = NSDateFormatter.dateFormatFromTemplate("dd.MM", options: 0, locale: NSLocale.currentLocale());
//        f.timeStyle = .NoStyle;
        return f;
    })();
    private static let fullFormatter = ({()-> NSDateFormatter in
        var f = NSDateFormatter();
        f.dateFormat = NSDateFormatter.dateFormatFromTemplate("dd.MM.yyyy", options: 0, locale: NSLocale.currentLocale());
//        f.timeStyle = .NoStyle;
        return f;
    })();
    
    private func formatTimestamp(ts:NSDate) -> String {
        let flags:NSCalendarUnit = [.Day, .Year];
        let components = NSCalendar.currentCalendar().components(flags, fromDate: ts, toDate: NSDate(), options: []);
        if (components.day == 1) {
            return "Yesterday";
        } else if (components.day < 1) {
            return ChatsListViewController.todaysFormatter.stringFromDate(ts);
        }
        if (components.year != 0) {
            return ChatsListViewController.fullFormatter.stringFromDate(ts);
        } else {
            return ChatsListViewController.defaultFormatter.stringFromDate(ts);
        }
        
    }

}

