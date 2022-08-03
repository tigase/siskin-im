//
//  BlockedContactsController.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 24/11/2019.
//  Copyright © 2019 Tigase, Inc. All rights reserved.
//

import UIKit
import Martin

class BlockedContactsController: UITableViewController {
        
    var activityIndicator: UIActivityIndicatorView!;
    
    private var allItems: [Item] = [];
    private var items: [Item] = [];
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);

        let clients = XmppService.instance.connectedClients;
        var items: [Item] = [];
        if !clients.isEmpty {
            showIndicator();
            let group = DispatchGroup();
            for client in clients {
                group.enter();
                DispatchQueue.global().async {
                    let account = client.userBareJid;
                    client.module(.blockingCommand).retrieveBlockedJids(completionHandler: { result in
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
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard items.count > 0 else {
            return nil;
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions -> UIMenu? in
            return UIMenu(title: "", children: [
                UIAction(title: NSLocalizedString("Unblock", comment: "button label"), image: UIImage(systemName: "hand.raised.slash"), attributes: [.destructive], handler: { action in
                    self.unblock(at: indexPath);
                })
            ]);
        };
    }
    
    func unblock(at indexPath: IndexPath) {
        let item = items[indexPath.row];
        guard let client = XmppService.instance.getClient(for: item.account), client.state == .connected() else {
            return;
        }
        
        let blockingModule = client.module(.blockingCommand);
        guard blockingModule.isAvailable else {
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
        self.items = allItems;
        tableView.reloadData();
    }
    
    func showIndicator() {
        if activityIndicator != nil {
            hideIndicator();
        }
        activityIndicator = UIActivityIndicatorView(style: .medium);
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
