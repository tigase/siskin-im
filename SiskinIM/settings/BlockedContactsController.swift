//
//  BlockedContactsController.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 24/11/2019.
//  Copyright © 2019 Tigase, Inc. All rights reserved.
//

import UIKit
import TigaseSwift

class BlockedContactsController: UITableViewController {
        
    var activityIndicator: UIActivityIndicatorView!;
    
    private var allItems: [Item] = [];
    private var items: [Item] = [];
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);

        let clients = XmppService.instance.getClients().filter({ (client) -> Bool in
            return client.state == .connected;
        });
        var items: [Item] = [];
        if !clients.isEmpty {
            showIndicator();
            let group = DispatchGroup();
            for client in clients {
                group.enter();
                DispatchQueue.global().async {
                    if let blockingModule: BlockingCommandModule = client.modulesManager.getModule(BlockingCommandModule.ID) {
                        let account = client.sessionObject.userBareJid!;
                        blockingModule.retrieveBlockedJids(completionHandler: { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(let jids):
                                    items.append(contentsOf: jids.map({ jid -> Item in
                                        return Item(account: account, jid: jid);
                                    }));
                                case .failure(_):
                                    break;
                                }
                            }
                            group.leave();
                        });
                    } else {
                        group.leave();
                    }
                }
            }
            group.notify(queue: DispatchQueue.main, execute: {
                self.allItems = items.sorted();
                self.updateItems();
                self.hideIndicator();
            })
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if items.count == 0 {
            return 1;
        }
        return items.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard items.count > 0 else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "BlockedContactTableViewEmptyCell", for: indexPath);
            return cell;
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "BlockedContactTableViewCell", for: indexPath);
        let item = items[indexPath.row];
        cell.textLabel?.text = item.jid.stringValue;
        cell.detailTextLabel?.text = item.account.stringValue;
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard items.count > 0 else {
            return nil;
        }
        let unblock = UITableViewRowAction(style: .destructive, title: "Unblock", handler: { action, indexPath in
            self.unblock(at: indexPath);
        })
        return [unblock];
    }
    
    func unblock(at indexPath: IndexPath) {
        let item = items[indexPath.row];
        guard let client = XmppService.instance.getClient(for: item.account), client.state == .connected, let blockingModule: BlockingCommandModule = client.modulesManager.getModule(BlockingCommandModule.ID), blockingModule.isAvailable else {
            return;
        }
        
        showIndicator();
        blockingModule.unblock(jids: [item.jid], completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                self?.hideIndicator();
            }
            switch result {
            case .success(_):
                DispatchQueue.main.async {
                    guard let that = self else {
                        return;
                    }
                    that.allItems.removeAll { (it) -> Bool in
                        return it == item;
                    };
                    if let idx = that.items.firstIndex(of: item) {
                        that.items.remove(at: idx);
                        that.tableView.performBatchUpdates({
                            that.tableView.deleteRows(at: [IndexPath(item: idx, section: 0)], with: .automatic);
                            if that.items.count == 0 {
                                that.tableView.insertRows(at: [IndexPath(item: 0, section: 0)], with: .automatic);
                            }
                        }, completion: nil);
                    }
                }
            case .failure(_):
                break;
            }
        });
    }
    
    func updateItems() {
//        let val = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased();
//        print("search field value:", val);
//        self.items = self.allItems.filter({ it in
//            return val.isEmpty || it.jid.stringValue.lowercased().contains(val) || it.account.stringValue.lowercased().contains(val);
//        });
        self.items = allItems;
        tableView.reloadData();
    }
    
    func showIndicator() {
        if activityIndicator != nil {
            hideIndicator();
        }
        activityIndicator = UIActivityIndicatorView(style: .gray);
        activityIndicator?.center = CGPoint(x: view.frame.width/2, y: view.frame.height/2);
        activityIndicator!.isHidden = false;
        activityIndicator!.startAnimating();
        view.addSubview(activityIndicator!);
        view.bringSubviewToFront(activityIndicator!);
    }
    
    func hideIndicator() {
        activityIndicator?.stopAnimating();
        activityIndicator?.removeFromSuperview();
        activityIndicator = nil;
    }
    
    struct Item: Equatable, Comparable {
        static func < (i1: BlockedContactsController.Item, i2: BlockedContactsController.Item) -> Bool {
            switch i1.jid.stringValue.compare(i2.jid.stringValue) {
            case.orderedAscending:
                return true;
            case .orderedDescending:
                return false;
            case .orderedSame:
                return i1.account.stringValue.compare(i2.account.stringValue) == .orderedAscending;
            }
        }
        
        let account: BareJID;
        let jid: JID;
    }
}
