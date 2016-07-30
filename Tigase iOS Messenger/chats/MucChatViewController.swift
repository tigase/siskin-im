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

class MucChatViewController: BaseChatViewController, UITableViewDataSource {

    var room: Room?;
    
    var numberOfMessages_: Int?;
    var numberOfMessages: Int {
        get {
            if numberOfMessages_ == nil {
                numberOfMessages_ = xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid);
            }
            return numberOfMessages_!;
        }
        set {
            numberOfMessages_ = newValue;
        }
    }
    var scrollToIndexPath: NSIndexPath?;
    
    private var getMessagesStmt: DBStatement!;
    
    override func viewDidLoad() {
        getMessagesStmt = xmppService.dbChatHistoryStore.getMessagesStatementForAccountAndJid();
        super.viewDidLoad()
        tableView.dataSource = self;
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
        let mucModule: MucModule? = xmppService.getClient(account)?.modulesManager?.getModule(MucModule.ID);
        room = mucModule?.roomsManager.get(jid.bareJid);
    }
    
    override func viewWillAppear(animated: Bool) {
        numberOfMessages_ = nil;
        super.viewWillAppear(animated);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MucChatViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MucChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        
    }
    
    override func viewDidDisappear(animated: Bool) {
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
        return numberOfMessages;
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        var cell:MucChatTableViewCell? = nil;
        xmppService.dbChatHistoryStore.forEachMessage(getMessagesStmt, account: account, jid: jid.bareJid, limit: 1, offset: indexPath.row) { (cursor) -> Void in
            let nickname: String? = cursor["author_nickname"];
            let incoming = nickname != self.room?.nickname;
            let id = incoming ? "MucChatTableViewCellIncoming" : "MucChatTableViewCellOutgoing"
            cell = tableView.dequeueReusableCellWithIdentifier(id, forIndexPath: indexPath) as? MucChatTableViewCell;
            if cell != nil {
                cell!.nicknameLabel?.text = nickname;
                if let authorJid: BareJID = cursor["author_jid"] {
                    cell!.avatarView?.image = self.xmppService.avatarManager.getAvatar(authorJid, account: self.account);
                } else {
                    cell!.avatarView?.image = self.xmppService.avatarManager.defaultAvatar;
                }
                cell!.setMessageText(cursor["data"]);
                cell!.setTimestamp(cursor["timestamp"]!);
            }
        }
        cell?.setNeedsUpdateConstraints();
        cell?.updateConstraintsIfNeeded();
        return cell!;
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
            let indexPath = NSIndexPath(forRow: self.numberOfMessages, inSection: 0);
            self.numberOfMessages += 1;
            self.tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Bottom);
            self.scrollToIndexPath(indexPath);
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
    
    func reloadData() {
        numberOfMessages_ = nil;
        tableView.reloadData();
        xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
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
        
    func scrollToIndexPath(indexPath: NSIndexPath) {
        self.scrollToIndexPath = indexPath;
        
        dispatch_after( dispatch_time(DISPATCH_TIME_NOW, 30 * Int64(NSEC_PER_MSEC)), dispatch_get_main_queue()) {
            guard self.scrollToIndexPath != nil else {
                return;
            }
            let index = self.scrollToIndexPath!;
            self.scrollToIndexPath = nil;
            
            UIView.animateWithDuration(0, animations: { ()-> Void in
                self.tableView.scrollToRowAtIndexPath(index, atScrollPosition: .None, animated: false);
            });
        }
    }
    
    override func scrollToBottom(animated: Bool) {
        let indexPath = NSIndexPath(forRow: numberOfMessages - 1, inSection: 0);
        scrollToIndexPath(indexPath);
    }
    
}
