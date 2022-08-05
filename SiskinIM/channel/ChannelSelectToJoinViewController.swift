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
import Martin
import TigaseLogging
import Shared

class ChannelSelectToJoinViewController: UITableViewController, UISearchResultsUpdating, ChannelSelectAccountAndComponentControllerDelgate {
    
    @IBOutlet var joinButton: UIBarButtonItem!;
    @IBOutlet var statusView: ChannelJoinStatusView!;
    
    weak var client: XMPPClient? {
        didSet {
            statusView.account = client?.userBareJid;
            needRefresh = true;
        }
    }
    
    var domain: String? {
        didSet {
            statusView.server = domain;
            needRefresh = true;
        }
    }
    
    @MainActor
    var joinConversation: (BareJID,String?)? {
        didSet {
            domain = joinConversation?.0.domain;
        }
    }
    
    @MainActor
    private var components: [ChannelsHelper.Component] = [];
    private var allItems: [DiscoveryModule.Item] = [];
    
    private var items: [DiscoveryModule.Item] = [];
    
    private var needRefresh: Bool = false;
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ChannelSelectToJoinViewController");
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.tableView.contentInsetAdjustmentBehavior = .always;
        let searchController = UISearchController(searchResultsController: nil);
        self.navigationItem.hidesSearchBarWhenScrolling = false;
        searchController.hidesNavigationBarDuringPresentation = false;
        searchController.searchResultsUpdater = self
        searchController.searchBar.searchBarStyle = .prominent;
        searchController.searchBar.isOpaque = false;
        searchController.searchBar.isTranslucent = true;
        searchController.searchBar.placeholder = NSLocalizedString("Search channels", comment: "search bar placeholder");
        self.navigationItem.searchController = searchController;
//        definesPresentationContext = true;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        if client == nil {
            if let account = AccountManager.defaultAccount ?? AccountManager.activeAccounts().map({ $0.name }).sorted().first {
                client = XmppService.instance.getClient(for: account);
            }
        }
        if needRefresh {
            self.refreshItems();
            needRefresh = false;
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
        queryTask?.cancel();
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
        cell.detailTextLabel?.text = item.jid.description;
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        self.joinButton.isEnabled = true;
    }
    
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        self.joinButton.isEnabled = false;
    }
    
    private var queryTask: Task<Void,Error>?;
    
    func updateSearchResults(for searchController: UISearchController) {
        updateItems();
        queryTask?.cancel();
        if let text = searchController.searchBar.text, let client = self.client {
            queryTask = Task {
                try await Task.sleep(nanoseconds: 2 * 1000 * 1000 * 1000)
                self.logger.debug("executing query for: \(text)");
                let items = await ChannelsHelper.queryChannel(for: client, at: components, name: text)
                self.logger.debug("got items: \(items)");
                DispatchQueue.main.async {
                    var changed = false;
                    for item in items {
                        if self.allItems.first(where: { $0.jid == item.jid }) == nil {
                            self.allItems.append(item);
                            changed = true;
                        }
                    }
                    if changed {
                        self.updateItems();
                    }
                }
            }
        }
    }
    
    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func changeAccountOrComponentClicked(_ sender: Any) {
        self.performSegue(withIdentifier: "ChannelSelectAccountAndComponentSegue", sender: sender);
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ChannelSelectAccountAndComponentController {
            destination.delegate = self;
        }
        if let destination = segue.destination as? ChannelJoinViewController {
            destination.client = self.client;
            if let selected = tableView.indexPathForSelectedRow {
                let item = self.items[selected.row];
                destination.channelJid = item.jid.bareJid;
                destination.name = item.name ?? item.jid.localPart;
                destination.componentType = self.components.first(where: { $0.jid.domain == item.jid.domain })?.type ?? .mix;
                destination.password = self.joinConversation?.1;
            }
        }
    }
    
    func operationStarted() {
        guard !(self.refreshControl?.isRefreshing ?? false) else {
            return;
        }
        self.tableView.refreshControl = UIRefreshControl();
        self.tableView.refreshControl?.attributedTitle = NSAttributedString(string: NSLocalizedString("Updating…", comment: "refresh conrol label"));
        self.tableView.refreshControl?.isHidden = false;
        self.tableView.refreshControl?.layoutIfNeeded();
        self.tableView.setContentOffset(CGPoint(x: 0, y: tableView.contentOffset.y - self.tableView.refreshControl!.frame.height), animated: true)
        self.tableView.refreshControl?.beginRefreshing();
    }
    
    @MainActor
    func operationFinished() {
        self.tableView.refreshControl?.endRefreshing();
        self.tableView.refreshControl = nil;
    }

    private var refreshTask: Task<Void,Error>?;
    
    private func refreshItems() {
        guard let client = self.client else {
            return;
        }
        let domain = self.domain ?? client.userBareJid.domain;
        refreshTask?.cancel();
        self.operationStarted();
        refreshTask = Task {
            defer {
                DispatchQueue.main.async {
                    self.operationFinished();
                }
            }
            let components = (try? await ChannelsHelper.findComponents(for: client, at: domain)) ?? [];
            self.components = components;
            if let data = self.joinConversation, let name = data.0.localPart {
                let items = await ChannelsHelper.queryChannel(for: client, at: components, name: name);
                DispatchQueue.main.async {
                    var changed = false;
                    for item in items {
                        if self.allItems.first(where: { $0.jid == item.jid }) == nil {
                            self.allItems.append(item);
                            changed = true;
                        }
                    }
                    if changed {
                        self.updateItems();
                    }
                }
            } else {
                let allItems = await ChannelsHelper.findChannels(for: client, at: components);
                DispatchQueue.main.async {
                    self.allItems = allItems;
                    self.updateItems();
                }
            }
        }
    }
    
    @MainActor
    private func updateItems() {
        let prefix = self.navigationItem.searchController?.searchBar.text ?? "";
        let items = prefix.isEmpty ? allItems : allItems.filter({ item -> Bool in
            return (item.name?.starts(with: prefix) ?? false) || item.jid.description.contains(prefix);
        });
        self.items = items.sorted(by: { (i1, i2) -> Bool in
            return (i1.name ?? i1.jid.description).caseInsensitiveCompare(i2.name ?? i2.jid.description) == .orderedAscending;
        });
        tableView.reloadData();
        joinButton.isEnabled = false;
    }
 
}

class ChannelJoinStatusView: UIBarButtonItem {
    
    var account: BareJID? {
        didSet {
            let value = NSMutableAttributedString(string: "\(NSLocalizedString("Account", comment: "channel join status view label")): ", attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor.secondaryLabel]);
            value.append(NSAttributedString(string: account?.description ?? NSLocalizedString("None", comment: "channel join status view label"), attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor(named: "tintColor")!]));
            accountLabel.attributedText = value;
        }
    }
    var server: String? {
        didSet {
            let value = NSMutableAttributedString(string: "\(NSLocalizedString("Component", comment: "channel join status view label")): ", attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor.secondaryLabel]);
            value.append(NSAttributedString(string: server ?? NSLocalizedString("Automatic", comment: "channel join status view label"), attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor(named: "tintColor")!]));
            serverLabel.attributedText = value;
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
        accountLabel.isUserInteractionEnabled = false;
        accountLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize);
        accountLabel.translatesAutoresizingMaskIntoConstraints = false;
        accountLabel.text = "\(NSLocalizedString("Account", comment: "channel join status view label")): \(NSLocalizedString("None", comment: "channel join status view label"))";
        self.serverLabel = UILabel();
        serverLabel.isUserInteractionEnabled = false;
        serverLabel.font = UIFont.systemFont(ofSize: UIFont.smallSystemFontSize);
        if #available(iOS 13.0, *) {
            serverLabel.textColor = UIColor.secondaryLabel;
        } else {
            serverLabel.textColor = UIColor.darkGray;
        }
        serverLabel.translatesAutoresizingMaskIntoConstraints = false;
        serverLabel.text = "\(NSLocalizedString("Component", comment: "channel join status view label")): \(NSLocalizedString("Automatic", comment: "channel join status view label"))";
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
