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
    
    override func viewDidLoad() {
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
        super.viewWillAppear(animated);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MucChatViewController.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(MucChatViewController.avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated);
        if isFirstTime {
            // scroll to bottom?
            let count = xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid);
            if count > 0 {
                let path = NSIndexPath(forRow: count - 1, inSection: 0);
                self.tableView.scrollToRowAtIndexPath(path, atScrollPosition: UITableViewScrollPosition.Bottom, animated: false);
                isFirstTime = false;
            }
        }
        xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
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
        return xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid);
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        var cell:MucChatTableViewCell? = nil;
        xmppService.dbChatHistoryStore.forEachMessage(account, jid: jid.bareJid, limit: 1, offset: indexPath.row) { (cursor) -> Void in
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
                cell!.messageTextView.text = cursor["data"];
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
        //reloadData();
        let pos = xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid) - 1;
        let indexPath = NSIndexPath(forRow: pos, inSection: 0);
        tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Bottom);
        self.tableView.scrollToRowAtIndexPath(indexPath, atScrollPosition: .None, animated: false);
        xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
    }
    
    func avatarChanged(notification: NSNotification) {
        // TODO: adjust this to make it work properly with MUC
        guard ((notification.userInfo?["jid"] as? BareJID) == jid.bareJid) else {
            return;
        }
        if let indexPaths = tableView.indexPathsForVisibleRows {
            tableView.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .None);
        }
    }
    
    func reloadData() {
        tableView.reloadData();
        xmppService.dbChatHistoryStore.markAsRead(account, jid: jid.bareJid);
    }
    
    @IBAction func sendClicked(sender: UIButton) {
        let text = messageField.text;
        guard !(text?.isEmpty != false) else {
            return;
        }

        guard room?.state == .joined else {
            return;
        }
        room!.sendMessage(text);
        messageField.text = nil;
    }
    
}
