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

        let clients = XmppService.instance.connectedClients;
        if !clients.isEmpty {
            showIndicator();
            Task {
                let newItems = await withTaskGroup(of: [Item].self, returning: [Item].self, body: { group in
                    for client in clients {
                        group.addTask(operation: {
                            let account = client.userBareJid;
                            if let jids = try? await client.module(.blockingCommand).retrieveBlockedJids() {
                                return jids.map({ Item(account: account, jid: $0); })
                            } else {
                                return [];
                            }
                        })
                    }
                    return await group.reduce(into: [Item](), { $0.append(contentsOf: $1) })
                })
                await MainActor.run(body: {
                    self.allItems = newItems;
                    self.updateItems();
                    self.hideIndicator();
                })
            }
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
        cell.textLabel?.text = item.jid.description;
        cell.detailTextLabel?.text = item.account.description;
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
        Task {
            do {
                try await blockingModule.unblock(jids: [item.jid]);
                await MainActor.run(body: {
                    self.allItems.removeAll { (it) -> Bool in
                        return it == item;
                    };
                    if let idx = self.items.firstIndex(of: item) {
                        self.items.remove(at: idx);
                        self.tableView.performBatchUpdates({
                            self.tableView.deleteRows(at: [IndexPath(item: idx, section: 0)], with: .automatic);
                            if self.items.count == 0 {
                                self.tableView.insertRows(at: [IndexPath(item: 0, section: 0)], with: .automatic);
                            }
                        }, completion: nil);
                    }
                })
            } catch {}
            await MainActor.run(body: {
                self.hideIndicator();
            })
        }
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
            switch i1.jid.description.compare(i2.jid.description) {
            case.orderedAscending:
                return true;
            case .orderedDescending:
                return false;
            case .orderedSame:
                return i1.account.description.compare(i2.account.description) == .orderedAscending;
            }
        }
        
        let account: BareJID;
        let jid: JID;
    }
}
