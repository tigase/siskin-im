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

class RosterViewController: UITableViewController, EventHandler, UIGestureRecognizerDelegate {

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
    lazy var rosterItemGetPositionByName:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM roster_items WHERE coalesce(name,jid) < :name");
    lazy var rosterItemsGetNamesByJidAndAccount:DBStatement! = try? self.dbConnection.prepareStatement("SELECT coalesce(name, jid) as display_name FROM roster_items WHERE jid = :jid AND (:account IS NULL OR account = :account)");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 48;//UITableViewAutomaticDimension;
        //tableView.estimatedRowHeight = 48;
        // Do any additional setup after loading the view, typically from a nib.
        let lpgr = UILongPressGestureRecognizer(target: self, action: #selector(RosterViewController.handleLongPress));
        lpgr.minimumPressDuration = 2.0;
        lpgr.delegate = self;
        tableView.addGestureRecognizer(lpgr);
        navigationItem.leftBarButtonItem = self.editButtonItem()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        reloadData();
        xmppService.registerEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(RosterViewController.reloadData), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }
    
    override func viewWillDisappear(animated: Bool) {
        xmppService.unregisterEventHandler(self, events: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
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
                let jid: BareJID = cursor["jid"]!;
                let account: BareJID = cursor["account"]!;
                let xmppClient = self.xmppService.getClient(account);
                let presenceModule:PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                let presence = presenceModule?.presenceStore.getBestPresence(jid);
                cell.statusLabel.text = presence?.status ?? jid.stringValue;
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
                let account: BareJID = cursor["account"]!;
                let jid: JID = cursor["jid"]!;
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
    
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            let params:[String:Any?] = ["offset": indexPath.row];
            do {
                try rosterItemsList.query(params) { cursor -> Void in
                    let account: BareJID = cursor["account"]!;
                    let jid: JID = cursor["jid"]!;
                    if let rosterModule:RosterModule = self.xmppService.getClient(account)?.modulesManager.getModule(RosterModule.ID) {
                        rosterModule.rosterStore.remove(jid, onSuccess: nil, onError: { (errorCondition) in
                            let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .Alert);
                            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil));
                            self.presentViewController(alert, animated: true, completion: nil);
                        })
                    }
                }
            } catch _ {
                
            }            
        }
    }
    
    func handleLongPress(gestureRecognizer:UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .Began else {
            return
        }

        let point = gestureRecognizer.locationInView(self.tableView);
        if let indexPath = self.tableView.indexPathForRowAtPoint(point) {
            print("long press detected at", indexPath);

            let params:[String:Any?] = ["offset": indexPath.row];
            do {
                try rosterItemsList.query(params) { cursor -> Void in
                    let account: BareJID = cursor["account"]!;
                    let jid: JID = cursor["jid"]!;
                    self.openEditItem(account, jid: jid);
                }
            } catch _ {
                
            }
        }
    }
    
    
    @IBAction func addBtnClicked(sender: UIBarButtonItem) {
        self.openEditItem(nil, jid: nil);
    }
    
    func openEditItem(account: BareJID?, jid: JID?) {
        let navigationController = self.storyboard?.instantiateViewControllerWithIdentifier("RosterItemEditNavigationController") as! UINavigationController;
        let itemEditController = navigationController.visibleViewController as? RosterItemEditViewController;
        itemEditController?.account = account;
        itemEditController?.jid = jid;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    func avatarChanged(notification: NSNotification) {
        let jid = notification.userInfo!["jid"] as! BareJID;
        let indexPaths = indexPathsForJid(jid);
        tableView.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .Automatic);
    }
    
    func reloadData() {
        tableView.reloadData();
    }
    
    func handleEvent(event: Event) {
        switch event {
        case let e as PresenceModule.ContactPresenceChanged:
            //reloadData();
            let indexPaths = indexPathsForJid(e.presence.from!.bareJid, account: e.sessionObject.userBareJid!);
            tableView.reloadRowsAtIndexPaths(indexPaths, withRowAnimation: .Automatic);
        case let e as RosterModule.ItemUpdatedEvent:
            let position = try! rosterItemGetPositionByName.scalar(e.rosterItem.name ?? e.rosterItem.jid.stringValue);
            let indexPath = NSIndexPath(forRow: position!, inSection: 0);
            switch e.action! {
            case .added:
                tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Fade);
            case .removed:
                tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade);
            default:
                tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic);
                break;
            }
        default:
            break;
        }
    }

    // works properly only if item is still in database! 
    // for insert, upadate is OK, but not for delete
    func indexPathsForJid(jid: BareJID, account: BareJID? = nil) -> [NSIndexPath] {
        var indexPaths = [NSIndexPath]();
        do {
            try rosterItemsGetNamesByJidAndAccount.query(jid.stringValue, account?.stringValue) { (cursor)->Void in
                let name:String = cursor["display_name"]!;
                let row = try! self.rosterItemGetPositionByName.scalar(name);
                indexPaths.append(NSIndexPath(forRow: row!, inSection: 0));
            }
        } catch _ {
            
        }
        return indexPaths;
    }
}

