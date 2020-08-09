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

class ChannelJoinViewController: UITableViewController {
    
    @IBOutlet var joinButton: UIBarButtonItem!;
    
    @IBOutlet var nameField: UILabel!;
    @IBOutlet var jidField: UILabel!;
    @IBOutlet var nicknameField: UITextField!;
    @IBOutlet var passwordField: UITextField!;
    
    var account: BareJID?;
    var channelJid: BareJID?;
    var name: String?;
    var componentType: ChannelsHelper.ComponentType = .mix;
    var passwordRequired: Bool = false;
    var action: Action = .join
    
    var mixInvitation: MixInvitation? {
        didSet {
            if let value = mixInvitation {
                channelJid = value.channel;
                componentType = .mix;
                action = .join;
                name = value.channel.stringValue;
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.tableView.contentInsetAdjustmentBehavior = .always;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.nameField.text = name;
        self.jidField.text = channelJid?.stringValue;
                
        switch action {
        case .join:
            if componentType == .muc, let discoModule: DiscoveryModule = XmppService.instance.getClient(for: account!)?.modulesManager.getModule(DiscoveryModule.ID) {
                operationStarted(message: "Checking...");
                discoModule.getInfo(for: JID(channelJid!), node: nil, completionHandler: { result in
                    switch result {
                    case .success(_, _, let features):
                        DispatchQueue.main.async {
                            self.passwordRequired = features.contains("muc_passwordprotected");
                            self.tableView.reloadData();
                            self.operationEnded();
                        }
                    case .failure(_, _):
                        DispatchQueue.main.async {
                            self.operationEnded();
                        }
                    }
                });
            }
            joinButton.title = "Join";
        default:
            joinButton.title = "Create";
            break;
        }
    }
    
    @objc func cancelClicked(_ sender: Any) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func joinClicked(_ sender: Any) {
        let nick = self.nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "";
        let password = (passwordField?.text?.isEmpty ?? true) ? nil : passwordField.text;
        guard let account = self.account, !nick.isEmpty else {
            return;
        }
        
        switch action {
        case .join:
            self.join(account: account, channelJid: self.channelJid!, componentType: componentType, nick: nick, password: password);
        case .create(let isPublic, let invitationOnly, let description, let avatar):
            self.create(account: account, channelJid: self.channelJid!, componentType: componentType, name: name!, description: description, nick: nick, isPublic: isPublic, invitationOnly: invitationOnly, avatar: avatar);
        }
     }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if !passwordRequired && section == 2 {
            return 0.1;
        }
        return super.tableView(tableView, heightForHeaderInSection: section);
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if !passwordRequired && section == 2 {
            return 0;
        }
        return super.tableView(tableView, numberOfRowsInSection: section);
    }
        
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if !passwordRequired && section == 2 {
            return 0.1;
        }
        return super.tableView(tableView, heightForFooterInSection: section);
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if !passwordRequired && section == 2 {
            return nil;
        }
        return super.tableView(tableView, titleForHeaderInSection: section);
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
    
    @IBAction func textFieldChanged(_ sender: Any) {
        let nick = self.nicknameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "";
        self.joinButton.isEnabled = (!nick.isEmpty) && ((!passwordRequired) || (!(passwordField.text?.isEmpty ?? true)));
    }
    
    private func create(account: BareJID, channelJid: BareJID, componentType: ChannelsHelper.ComponentType, name: String, description: String?, nick: String, isPublic: Bool, invitationOnly: Bool, avatar: UIImage?) {
        switch componentType {
        case .mix:
            guard let client = XmppService.instance.getClient(for: account) else {
                return;
            }
            
            guard let mixModule: MixModule = client.modulesManager.getModule(MixModule.ID), let avatarModule: PEPUserAvatarModule = client.modulesManager.getModule(PEPUserAvatarModule.ID) else {
                return;
            }
            self.operationStarted(message: "Creating channel...")
                
            mixModule.create(channel: channelJid.localPart, at: BareJID(domain: channelJid.domain), completionHandler: { [weak self] result in
                switch result {
                case .success(let channelJid):
                        mixModule.join(channel: channelJid, withNick: nick, completionHandler: { result in
                            DispatchQueue.main.async {
                                self?.operationEnded();
                            }
                            switch result {
                            case .success(_):
                                DispatchQueue.main.async {
                                    self?.dismiss(animated: true, completion: nil);
                                }
                            case .failure(let errorCondition, _):
                                DispatchQueue.main.async {
                                    guard let that = self else {
                                        return;
                                    }
                                    let alert = UIAlertController(title: "Error occurred", message: "Could not join newly created channel '\(channelJid)' on the server. Got following error: \(errorCondition.rawValue)", preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                                    that.present(alert, animated: true, completion: nil);
                                }
                            }
                        })
                        mixModule.publishInfo(for: channelJid, info: ChannelInfo(name: name, description: description, contact: []), completionHandler: nil);
                        if let avatarData = avatar?.scaled(maxWidthOrHeight: 512.0)?.jpegData(compressionQuality: 0.8) {
                            avatarModule.publishAvatar(at: channelJid, data: avatarData, mimeType: "image/jpeg", completionHandler: { result in
                                print("avatar publication result:", result);
                            });
                        }
                        if invitationOnly {
                            mixModule.changeAccessPolicy(of: channelJid, isPrivate: invitationOnly, completionHandler: { result in
                                print("changed channel access policy:", result);
                            })
                        }
                    case .failure(let errorCondition):
                        DispatchQueue.main.async {
                            self?.operationEnded();
                            guard let that = self else {
                                return;
                            }
                            let alert = UIAlertController(title: "Error occurred", message: "Could not create channel on the server. Got following error: \(errorCondition.rawValue)", preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                            that.present(alert, animated: true, completion: nil);
                        }
                    }
                })
                break;
        case .muc:
            guard let client = XmppService.instance.getClient(for: account), let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            let roomName = isPublic ? channelJid.localPart! : UUID().uuidString;
            _ = mucModule.join(roomName: roomName, mucServer: channelJid.domain, nickname: nick, ifCreated: { room in
                mucModule.getRoomConfiguration(roomJid: room.jid, onSuccess: { (config) in
                    if let roomNameField: TextSingleField = config.getField(named: "muc#roomconfig_roomname") {
                        roomNameField.value = name;
                    }
                    if let membersOnlyField: BooleanField = config.getField(named: "muc#roomconfig_membersonly") {
                        membersOnlyField.value = invitationOnly;
                    }
                    if let persistantField: BooleanField = config.getField(named: "muc#roomconfig_persistentroom") {
                        persistantField.value = true;
                    }
                    if let publicallySeachableField: BooleanField = config.getField(named: "muc#roomconfig_publicroom") {
                        publicallySeachableField.value = isPublic;
                    }
                    mucModule.setRoomConfiguration(roomJid: room.jid, configuration: config, onSuccess: {
                        print("unlocked room", room.jid);
//                        participants.forEach({ (participant) in
//                            mucModule.invite(to: room, invitee: participant, reason: "You are invied to join conversation \(roomName) at \(room.roomJid)");
//                        })
                        PEPBookmarksModule.updateOrAdd(for: account, bookmark: Bookmarks.Conference(name: roomName, jid: room.jid, autojoin: true, nick: nick, password: nil));
                    }, onError: nil);
                }, onError: nil);
            }, onJoined: { room in
                DispatchQueue.main.async { [weak self] in
                    self?.dismiss(animated: true, completion: nil);
                }
                if let vCardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) {
                    let vcard = VCard();
                    if let binval = avatar?.scaled(maxWidthOrHeight: 512.0)?.jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                        vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
                    }
                    vCardTempModule.publishVCard(vcard, to: room.roomJid);
                }
                if description != nil {
                    mucModule.setRoomSubject(roomJid: room.roomJid, newSubject: description);
                }
                room.registerForTigasePushNotification(true, completionHandler: { (result) in
                    print("automatically enabled push for:", room.roomJid, "result:", result);
                })
            });
        }
    }
    
    private func join(account: BareJID, channelJid: BareJID, componentType: ChannelsHelper.ComponentType, nick: String, password: String?) {
        guard (!passwordRequired) || (password != nil) else {
            return;
        }
        
        switch componentType {
         case .mix:
             guard let channelJid = self.channelJid, let mixModule: MixModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MixModule.ID) else {
                 return;
             }
             self.operationStarted(message: "Joining...");
             mixModule.join(channel: channelJid, withNick: nick, invitation: mixInvitation, completionHandler: { result in
                 switch result {
                 case .success(_):
                     // we have joined, so all what we need to do is close this window
                     DispatchQueue.main.async {
                         self.operationEnded();
                         self.dismiss(animated: true, completion: nil);
                     }
                 case .failure(let errorCondition, let response):
                     DispatchQueue.main.async {
                         self.operationEnded();
                         let alert = UIAlertController(title: "Could not join", message: "It was not possible to join a channel. The server returned an error: \(response?.errorText ?? errorCondition.rawValue)", preferredStyle: .alert);
                         alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                         alert.present(alert, animated: true, completion: nil);
                     }
                 }
             });
         case .muc:
             guard let mucModule: MucModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MucModule.ID) else {
                 return;
             }
             let room = channelJid;
             _ = mucModule.join(roomName: room.localPart!, mucServer: room.domain, nickname: nick, password: password);
             PEPBookmarksModule.updateOrAdd(for: account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nick, password: password));
             DispatchQueue.main.async {
                 self.dismiss(animated: true, completion: nil);
             }
         }
    }
    
    enum Action {
        case create(isPublic: Bool, invitationOnly: Bool, description: String?, avatar: UIImage?)
        case join
    }
}
