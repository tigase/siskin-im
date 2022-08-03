//
// ChannelBlockedUsersController.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//
import UIKit
import Martin

class ChannelBlockedUsersController: UITableViewController {

    var channel: Channel!;
    
    private var jids: [BareJID] = [] {
        didSet {
            tableView.reloadData();
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        if let mixModule = channel.context?.module(.mix) {
            self.operationStarted(message: NSLocalizedString("Refreshing…", comment: "channel block users view operation"));
            mixModule.retrieveBanned(for: channel.channelJid, completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    self?.operationEnded();
                    switch result {
                    case .success(let blocked):
                        self?.jids = blocked.sorted();
                    case .failure(_):
                        break;
                    }
                }
            })
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return jids.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let jid = jids[indexPath.row];
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChannelBlockedCellView", for: indexPath);
        cell.textLabel?.text = jid.stringValue;
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let jid = jids[indexPath.row];
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { menu -> UIMenu? in
            let unblock = UIAction(title: NSLocalizedString("Unblock", comment: "action"), image: UIImage(systemName: "trash"), handler: { action in
                if let mixModule = self.channel.context?.module(.mix) {
                    self.operationStarted(message: NSLocalizedString("Updating…", comment: "channel block users view operation"));
                    mixModule.denyAccess(to: self.channel.channelJid, for: jid, value: false, completionHandler: { [weak self] result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(_):
                                self?.jids = self?.jids.filter { $0 != jid } ?? [];
                            case .failure(_):
                                break;
                            }
                            self?.operationEnded();
                        }
                    })
                }
            });
            return UIMenu(title: "", children: [unblock]);
        })
    }
    
    func operationStarted(message: String) {
        self.tableView.refreshControl = UIRefreshControl();
        self.tableView.refreshControl?.attributedTitle = NSAttributedString(string: message);
        self.tableView.refreshControl?.isHidden = false;
        self.tableView.refreshControl?.layoutIfNeeded();
        self.tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y - self.tableView.refreshControl!.frame.height), animated: true)
        self.tableView.refreshControl?.beginRefreshing();
    }
    
    func operationEnded() {
        self.tableView.refreshControl?.endRefreshing();
        self.tableView.refreshControl = nil;
    }

}
