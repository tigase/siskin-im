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
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.dbConnection;
    }
    
    var xmppService:XmppService {
        let appDelegate = UIApplication.shared.delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    fileprivate lazy var rosterItemsCount:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM roster_items");
    fileprivate lazy var rosterItemsList:DBStatement! = try? self.dbConnection.prepareStatement("SELECT id, account, jid, name FROM roster_items ORDER BY coalesce(name, jid) LIMIT 1 OFFSET :offset");
    fileprivate lazy var rosterItemGetPositionByName:DBStatement! = try? self.dbConnection.prepareStatement("SELECT count(id) FROM roster_items WHERE coalesce(name,jid) < :name");
    fileprivate lazy var rosterItemsGetNamesByJidAndAccount:DBStatement! = try? self.dbConnection.prepareStatement("SELECT coalesce(name, jid) as display_name FROM roster_items WHERE jid = :jid AND (:account IS NULL OR account = :account)");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = 48;//UITableViewAutomaticDimension;
        //tableView.estimatedRowHeight = 48;
        // Do any additional setup after loading the view, typically from a nib.
        let lpgr = UILongPressGestureRecognizer(target: self, action: #selector(RosterViewController.handleLongPress));
        lpgr.minimumPressDuration = 2.0;
        lpgr.delegate = self;
        tableView.addGestureRecognizer(lpgr);
        navigationItem.leftBarButtonItem = self.editButtonItem
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(_ animated: Bool) {
        xmppService.registerEventHandler(self, for: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
        reloadData();
        NotificationCenter.default.addObserver(self, selector: #selector(RosterViewController.reloadData), name: AvatarManager.AVATAR_CHANGED, object: nil);
        super.viewWillAppear(animated);
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        xmppService.unregisterEventHandler(self, for: PresenceModule.ContactPresenceChanged.TYPE, RosterModule.ItemUpdatedEvent.TYPE);
        super.viewWillDisappear(animated);
        NotificationCenter.default.removeObserver(self);
    }

    override func numberOfSections(in: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return try! rosterItemsCount.scalar() ?? 0;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = "RosterItemTableViewCell";
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath as IndexPath) as! RosterItemTableViewCell;
        
        let params:[String:Any?] = ["offset": indexPath.row];
        do {
            try rosterItemsList.query(params) { cursor -> Void in
                cell.nameLabel.text = cursor["name"];
                let jid: BareJID = cursor["jid"]!;
                let account: BareJID = cursor["account"]!;
                let xmppClient = self.xmppService.getClient(forJid: account);
                let presenceModule:PresenceModule? = xmppClient?.modulesManager.getModule(PresenceModule.ID);
                let presence = presenceModule?.presenceStore.getBestPresence(for: jid);
                cell.statusLabel.text = presence?.status ?? jid.stringValue;
                cell.avatarStatusView.setStatus(presence?.show);
                cell.avatarStatusView.setAvatar(self.xmppService.avatarManager.getAvatar(for: jid, account: account));
            }
        } catch _ {
            cell.nameLabel.text = "DBError";
        }
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let params:[String:Any?] = ["offset": indexPath.row];
        do {
            try rosterItemsList.query(params) { cursor -> Void in
                let account: BareJID = cursor["account"]!;
                let jid: JID = cursor["jid"]!;
                let xmppClient = self.xmppService.getClient(forJid: account);
                let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                
                guard messageModule != nil else {
                    return;
                }
                
                if !self.xmppService.dbChatStore.isFor(xmppClient!.sessionObject, jid: jid.bareJid) {
                    _ = messageModule!.createChat(with: jid);
                }
                
                let destination = self.storyboard!.instantiateViewController(withIdentifier: "ChatViewNavigationController") as! UINavigationController;
                let chatController = destination.childViewControllers[0] as! ChatViewController;
                chatController.hidesBottomBarWhenPushed = true;
                chatController.account = account;
                chatController.jid = jid;
                self.showDetailViewController(destination, sender: self);
            }
        } catch _ {

        }
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let params:[String:Any?] = ["offset": indexPath.row];
            do {
                try rosterItemsList.query(params) { cursor -> Void in
                    let account: BareJID = cursor["account"]!;
                    let jid: JID = cursor["jid"]!;
                    if let rosterModule:RosterModule = self.xmppService.getClient(forJid: account)?.modulesManager.getModule(RosterModule.ID) {
                        rosterModule.rosterStore.remove(jid: jid, onSuccess: nil, onError: { (errorCondition) in
                            let alert = UIAlertController.init(title: "Failure", message: "Server returned error: " + (errorCondition?.rawValue ?? "Operation timed out"), preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                            self.present(alert, animated: true, completion: nil);
                        })
                    }
                }
            } catch _ {
                
            }            
        }
    }
    
    func handleLongPress(_ gestureRecognizer:UILongPressGestureRecognizer) {
        guard gestureRecognizer.state == .began else {
            return
        }

        let point = gestureRecognizer.location(in: self.tableView);
        if let indexPath = self.tableView.indexPathForRow(at: point) {
            print("long press detected at", indexPath);

            let params:[String:Any?] = ["offset": indexPath.row];
            do {
                try rosterItemsList.query(params) { cursor -> Void in
                    let account: BareJID = cursor["account"]!;
                    let jid: JID = cursor["jid"]!;
                    self.openEditItem(for: account, jid: jid);
                }
            } catch _ {
                
            }
        }
    }
    
    
    @IBAction func addBtnClicked(_ sender: UIBarButtonItem) {
        self.openEditItem(for: nil, jid: nil);
    }
    
    func openEditItem(for account: BareJID?, jid: JID?) {
        let navigationController = self.storyboard?.instantiateViewController(withIdentifier: "RosterItemEditNavigationController") as! UINavigationController;
        let itemEditController = navigationController.visibleViewController as? RosterItemEditViewController;
        itemEditController?.account = account;
        itemEditController?.jid = jid;
        self.showDetailViewController(navigationController, sender: self);
    }
    
    func avatarChanged(_ notification: NSNotification) {
        DispatchQueue.main.async() {
            let jid = notification.userInfo!["jid"] as! BareJID;
            let indexPaths = self.indexPaths(for: jid);
            self.tableView.reloadRows(at: indexPaths, with: .automatic);
        }
    }
    
    func reloadData() {
        DispatchQueue.main.async() {
            self.tableView.reloadData();
        }
    }
    
    func handle(event: Event) {
        switch event {
        case let e as PresenceModule.ContactPresenceChanged:
            //reloadData();
            guard e.sessionObject.userBareJid != nil, let from = e.presence.from else {
                // guard for possible malformed presence
                return;
            }
            
            DispatchQueue.main.async() {
                let indexPaths = self.indexPaths(for: from.bareJid, account: e.sessionObject.userBareJid!);
                self.tableView.reloadRows(at: indexPaths, with: .automatic);
            }
        case let e as RosterModule.ItemUpdatedEvent:
            guard e.rosterItem != nil else {
                tableView.reloadData();
                return;
            }

            DispatchQueue.main.async() {
                let position = try! self.rosterItemGetPositionByName.scalar(e.rosterItem?.name ?? e.rosterItem!.jid.stringValue);
                let indexPath = IndexPath(row: position!, section: 0);
                switch e.action! {
                case .added:
                    self.tableView.insertRows(at: [indexPath], with: .fade);
                case .removed:
                    self.tableView.deleteRows(at: [indexPath], with: .fade);
                default:
                    self.tableView.reloadRows(at: [indexPath], with: .automatic);
                    break;
                }
            }
        default:
            break;
        }
    }

    // works properly only if item is still in database! 
    // for insert, upadate is OK, but not for delete
    func indexPaths(for jid: BareJID, account: BareJID? = nil) -> [IndexPath] {
        var indexPaths = [IndexPath]();
        do {
            try rosterItemsGetNamesByJidAndAccount.query(jid.stringValue, account?.stringValue) { (cursor)->Void in
                let name:String = cursor["display_name"]!;
                let row = try! self.rosterItemGetPositionByName.scalar(name);
                indexPaths.append(IndexPath(row: row!, section: 0));
            }
        } catch _ {
            
        }
        return indexPaths;
    }
}

