//
// RosterViewController.swift
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

class RosterViewController: UITableViewController, EventHandler {

    var dbConnection:DBConnection {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.dbConnection;
    }
    
    var xmppService:XmppService {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    lazy var rosterItemsCount:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM roster_items");
    lazy var rosterItemsList:DBStatement! = try? self.dbConnection.prepareStatement("SELECT id, account, jid, name FROM roster_items ORDER BY coalesce(name, jid) LIMIT 1 OFFSET :offset");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 48;//UITableViewAutomaticDimension;
        //tableView.estimatedRowHeight = 48;
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        reloadData();
        xmppService.registerEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(RosterViewController.reloadData), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }
    
    override func viewWillDisappear(animated: Bool) {
        xmppService.unregisterEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE);
        super.viewWillDisappear(animated);
        NSNotificationCenter.defaultCenter().removeObserver(self);
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return try! rosterItemsCount.scalar() ?? 0;
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cellIdentifier = "RosterItemTableViewCell";
        let cell = tableView.dequeueReusableCellWithIdentifier(cellIdentifier, forIndexPath: indexPath) as! RosterItemTableViewCell;
        
        let params:[String:Any?] = ["offset": indexPath.row];
        do {
            try rosterItemsList.query(params) { cursor -> Void in
                cell.nameLabel.text = cursor["name"];
                let jidStr:String = cursor["jid"]!;
                let jid = BareJID(jidStr);
                let account = BareJID(cursor["account"]!);
                let xmppClient = self.xmppService.getClient(account);
                let presenceModule:PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                let presence = presenceModule?.presenceStore.getBestPresence(jid);
                cell.statusLabel.text = presence?.status ?? jidStr;
                cell.avatarStatusView.setStatus(presence?.show);
                cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.getAvatar(jid, account: account));
            }
        } catch _ {
            cell.nameLabel.text = "DBError";
        }
        return cell;
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let params:[String:Any?] = ["offset": indexPath.row];
        do {
            try rosterItemsList.query(params) { cursor -> Void in
                let account = BareJID(cursor["account"]!);
                let jid = JID(cursor["jid"]!);
                let xmppClient = self.xmppService.getClient(account);
                let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                
                guard messageModule != nil else {
                    return;
                }
                
                if !self.xmppService.dbChatStore.isFor(xmppClient!.sessionObject, jid: jid.bareJid) {
                    messageModule!.createChat(jid);
                }
                
                let destination = self.storyboard!.instantiateViewControllerWithIdentifier("ChatViewNavigationController") as! UINavigationController;
                let chatController = destination.childViewControllers[0] as! ChatViewController;
                chatController.hidesBottomBarWhenPushed = true;
                chatController.account = account;
                chatController.jid = jid;
                self.showDetailViewController(destination, sender: self);
            }
        } catch _ {

        }
    }
    
    func reloadData() {
        tableView.reloadData();
    }
    
    func handleEvent(event: Event) {
        switch event {
        case is PresenceModule.ContactPresenceChanged:
            reloadData();
        default:
            break;
        }
    }
}

