//
// ChannelJoinViewController.swift
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
import TigaseSwift

class ChannelSelectToJoinViewController: UITableViewController, UISearchResultsUpdating, ChannelSelectAccountAndComponentControllerDelgate {
    
    @IBOutlet var joinButton: UIBarButtonItem!;
    @IBOutlet var statusView: ChannelJoinStatusView!;
    
    var account: BareJID? {
        didSet {
            statusView.account = account;
            needRefresh = true;
        }
    }
    var domain: String? {
        didSet {
            statusView.server = domain;
            needRefresh = true;
        }
    }
    
    private var components: [ChannelsHelper.Component] = [];
    private var allItems: [DiscoveryModule.Item] = [];
    
    private var items: [DiscoveryModule.Item] = [];
    
    private var needRefresh: Bool = false;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.tableView.contentInsetAdjustmentBehavior = .always;
        let searchController = UISearchController(searchResultsController: nil);
        self.navigationItem.hidesSearchBarWhenScrolling = false;
        searchController.dimsBackgroundDuringPresentation = false;
        searchController.hidesNavigationBarDuringPresentation = false;
        searchController.searchResultsUpdater = self
        searchController.searchBar.searchBarStyle = .prominent;
        searchController.searchBar.isOpaque = false;
        searchController.searchBar.isTranslucent = true;
        searchController.searchBar.placeholder = "Search channels";
        self.navigationItem.searchController = searchController;
//        definesPresentationContext = true;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        if account == nil {
            self.account = AccountManager.getActiveAccounts().first;
        }
        if needRefresh {
            self.refreshItems();
            needRefresh = false;
        }
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return self.items.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChannelJoinCellView", for: indexPath);
        let item = items[indexPath.row];
        cell.textLabel?.text = item.name ?? item.jid.localPart;
        cell.detailTextLabel?.text = item.jid.stringValue;
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.joinButton.isEnabled = true;
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        self.joinButton.isEnabled = false;
    }
    
    private var queryRemote: String?;
    
    func updateSearchResults(for searchController: UISearchController) {
        updateItems();
        self.queryRemote = searchController.searchBar.text;
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: { [weak self] in
            guard let that = self, let remoteQuery = that.queryRemote, let account = that.account, let text = searchController.searchBar.text, remoteQuery == text else {
                print("remote query", self?.queryRemote, "text:", searchController.searchBar.text)
                return;
            }
            that.queryRemote = nil;
            print("executing query for:", text);
            ChannelsHelper.queryChannel(for: account, at: that.components, name: text, completionHandler: { result in
                switch result {
                case .success(let items):
                    print("got items:", items);
                    DispatchQueue.main.async {
                        guard let that = self else {
                            return;
                        }
                        var changed = false;
                        for item in items {
                            if that.allItems.first(where: { $0.jid == item.jid }) == nil {
                                that.allItems.append(item);
                                changed = true;
                            }
                        }
                        if changed {
                            that.updateItems();
                        }
                    }
                case .failure(let err):
                    print("got error:", err);
                }
            })
        });
    }
    
    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ChannelSelectAccountAndComponentController {
            destination.delegate = self;
        }
        if let destination = segue.destination as? ChannelJoinViewController {
            destination.account = self.account;
            if let selected = tableView.indexPathForSelectedRow {
                let item = self.items[selected.row];
                destination.channelJid = item.jid.bareJid;
                destination.name = item.name ?? item.jid.localPart;
                destination.componentType = self.components.first(where: { $0.jid.domain == item.jid.domain })?.type ?? .mix;
            }
        }
    }
    
    func operationStarted() {
        guard !(self.refreshControl?.isRefreshing ?? false) else {
            return;
        }
        self.tableView.refreshControl = UIRefreshControl();
        self.tableView.refreshControl?.attributedTitle = NSAttributedString(string: "Updating...");
        self.tableView.refreshControl?.isHidden = false;
        self.tableView.refreshControl?.layoutIfNeeded();
        self.tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y - self.tableView.refreshControl!.frame.height), animated: true)
        self.tableView.refreshControl?.beginRefreshing();
    }
    
    func operationFinished() {
        self.tableView.refreshControl?.endRefreshing();
        self.tableView.refreshControl = nil;
    }

    private func refreshItems() {
        guard let account = self.account else {
            return;
        }
        let domain = self.domain ?? account.domain;
        self.operationStarted();
        ChannelsHelper.findComponents(for: account, at: domain, completionHandler: { [weak self] components in
            guard let that = self, that.account == account else {
                return;
            }
            let currDomain = that.domain ?? account.domain;
            guard currDomain == domain else {
                return;
            }
            that.components = components;
            ChannelsHelper.findChannels(for: account, at: components, completionHandler: { [weak self] allItems in
                guard let that = self, that.account == account else {
                    return;
                }
                let currDomain = that.domain ?? account.domain;
                guard currDomain == domain else {
                    return;
                }
                that.allItems = allItems;
                that.updateItems();
                that.operationFinished();
            })
        })
    }
    
    private func updateItems() {
        let prefix = self.navigationItem.searchController?.searchBar.text ?? "";
        let items = prefix.isEmpty ? allItems : allItems.filter({ item -> Bool in
            return (item.name?.starts(with: prefix) ?? false) || item.jid.stringValue.contains(prefix);
        });
        self.items = items.sorted(by: { (i1, i2) -> Bool in
            return (i1.name ?? i1.jid.stringValue).caseInsensitiveCompare(i2.name ?? i2.jid.stringValue) == .orderedAscending;
        });
        tableView.reloadData();
        joinButton.isEnabled = false;
    }
 
}

class ChannelJoinStatusView: UIBarButtonItem {
    
    var account: BareJID? {
        didSet {
            accountLabel.text = account == nil ? nil : "Account: \(account!.stringValue)";
        }
    }
    var server: String? {
        didSet {
            serverLabel.text = "Component: \(server ?? "Automatic")";
        }
    }
    
    private var accountLabel: UILabel!;
    private var serverLabel: UILabel!;
    
    override init() {
        super.init();
        setup();
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
    
    func setup() {
        let view = UIView();
        view.translatesAutoresizingMaskIntoConstraints = false;
        self.accountLabel = UILabel();
        accountLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize);
        accountLabel.translatesAutoresizingMaskIntoConstraints = false;
        accountLabel.text = "Account: test@hi-low.eu";
        self.serverLabel = UILabel();
        serverLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize);
        if #available(iOS 13.0, *) {
            serverLabel.textColor = UIColor.secondaryLabel;
        } else {
            serverLabel.textColor = UIColor.darkGray;
        }
        serverLabel.translatesAutoresizingMaskIntoConstraints = false;
        serverLabel.text = "Component: Automatic";
        view.addSubview(accountLabel);
        view.addSubview(serverLabel);
        
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: accountLabel.topAnchor),
            view.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: accountLabel.trailingAnchor),
            accountLabel.bottomAnchor.constraint(equalTo: serverLabel.topAnchor),
            view.leadingAnchor.constraint(equalTo: serverLabel.leadingAnchor),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: serverLabel.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: serverLabel.bottomAnchor)
        ])
        
        self.customView =  view;
    }
    
}
