//
// ChannelCreateViewController.swift
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

class ChannelCreateViewController: UITableViewController, ChannelSelectAccountAndComponentControllerDelgate {
 
    @IBOutlet var joinButton: UIBarButtonItem!;
    @IBOutlet var statusView: ChannelJoinStatusView!;
    @IBOutlet var channelNameField: UITextField!;
    @IBOutlet var channelIdField: UITextField!;
    
    var client: XMPPClient? {
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
    var kind: ChannelKind = .adhoc;
    
    private var components: [ChannelsHelper.Component] = [] {
        didSet {
            updateJoinButtonStatus();
        }
    }
    private var invitationOnly: Bool = true;
    private var useMix: Bool = false;
    private var needRefresh = false;
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        if client == nil {
            if let account = AccountManager.getActiveAccounts().first?.name {
                client = XmppService.instance.getClient(for: account);
            }
        }
        if needRefresh {
            self.refresh();
            needRefresh = false;
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath);
        if indexPath.section == 1 {
            let view = UISwitch();
            view.isOn = self.invitationOnly;
            view.addTarget(self, action: #selector(invitationOnlySwitchChanged(_:)), for: .valueChanged);
            cell.accessoryView = view;
        }
        if indexPath.section == 3 {
            let view = UISwitch();
            view.isOn = self.useMix;
            view.addTarget(self, action: #selector(mixSwitchChanged(_:)), for: .valueChanged);
            cell.accessoryView = view;
        }
        return cell;
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        let count = super.numberOfSections(in: tableView);
        if components.map({ $0.type }).contains(.mix) {
            return count;
        }
        return count - 1;
    }

    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if kind == .adhoc && section == 2 {
            return 0.1;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if kind == .adhoc && section == 2 {
            return nil;
        }
        return super.tableView(tableView, titleForHeaderInSection: section);
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if kind == .adhoc && section == 2 {
            return 0;
        }
        return super.tableView(tableView, numberOfRowsInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if kind == .adhoc && section == 2 {
            return 0.1;
        }
        return super.tableView(tableView, heightForFooterInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if kind == .adhoc && section == 2 {
            return nil;
        }
        return super.tableView(tableView, titleForFooterInSection: section);
    }
    
    @objc func invitationOnlySwitchChanged(_ sender: UISwitch) {
        invitationOnly = sender.isOn;
    }
    
    @objc func mixSwitchChanged(_ sender: UISwitch) {
        useMix = sender.isOn;
        updateJoinButtonStatus();
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let destination = segue.destination as? ChannelSelectAccountAndComponentController {
            destination.delegate = self;
        }
        if let destination = segue.destination as? ChannelJoinViewController {
            destination.action = .create(isPublic: kind == .stable, invitationOnly: invitationOnly, description: nil, avatar: nil);
            destination.client = self.client;
            let component = self.components.first(where: { $0.type == (useMix ? .mix : .muc) })!;
            destination.channelJid = BareJID(domain: component.jid.domain);
            if kind == .stable {
                if let val = self.channelIdField.text, !val.isEmpty {
                    destination.channelJid = BareJID(localPart: val, domain: component.jid.domain);
                }
            }
            destination.name = channelNameField.text!;
            destination.componentType = useMix ? .mix : .muc;
        }
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

    @IBAction func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }

    @IBAction func textFieldChanged(_ sender: Any) {
        updateJoinButtonStatus();
    }
    
    private func updateJoinButtonStatus() {
        let name = self.channelNameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "";
        let channelId = self.channelIdField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "";
        self.joinButton.isEnabled = (!name.isEmpty) && (kind == .adhoc || !channelId.isEmpty) && self.components.contains(where: { $0.type == (useMix ? .mix : .muc) });
    }

    private func refresh() {
        guard let client = self.client else {
            return;
        }
        let domain = self.domain ?? client.userBareJid.domain;
        self.operationStarted(message: NSLocalizedString("Checking…", comment: "channel create view operation label"));
        ChannelsHelper.findComponents(for: client, at: domain, completionHandler: { components in
            DispatchQueue.main.async {
                self.components = components;
                let types = Set(components.map({ $0.type }));
                if types.count == 1 {
                    switch types.first! {
                    case .mix:
                        self.useMix = true;
                    case .muc:
                        self.useMix = false;
                    }
                }
                self.tableView.reloadData();
                self.updateJoinButtonStatus();
                self.operationEnded();
                if components.isEmpty {
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: NSLocalizedString("Service unavailable", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("There is no service supporting channels for domain %@", comment: "alert message"), domain), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default));
                        self.present(alert, animated: true, completion: nil);
                    }
                }
            }
        })
    }
    
    enum ChannelKind {
        case stable
        case adhoc
    }
    
}
