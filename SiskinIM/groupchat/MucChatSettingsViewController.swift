//
// MucChatSettingsViewController.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import Combine
import Shared

class MucChatSettingsViewController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet var roomNameField: UILabel!;
    @IBOutlet var roomAvatarView: AvatarView!
    @IBOutlet var roomSubjectField: UILabel!;
    @IBOutlet var pushNotificationsSwitch: UISwitch!;
    @IBOutlet var notificationsField: UILabel!;
    @IBOutlet var encryptionField: UILabel!;
        
    fileprivate var activityIndicator: UIActivityIndicatorView?;
    
    var room: Room!;
    
    @Published
    private var canEditVCard: Bool = false;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewWillAppear(_ animated: Bool) {
        roomAvatarView.layer.cornerRadius = roomAvatarView.frame.width / 2;
        roomAvatarView.layer.masksToBounds = true;
//        roomAvatarView.widthAnchor.constraint(equalTo: roomAvatarView.heightAnchor).isActive = true;
        room.optionsPublisher.compactMap({ $0.name }).receive(on: DispatchQueue.main).assign(to: \.text, on: roomNameField).store(in: &cancellables);
        room.avatarPublisher.map({ $0 ?? AvatarManager.instance.defaultGroupchatAvatar }).receive(on: DispatchQueue.main).assign(to: \.avatar, on: roomAvatarView).store(in: &cancellables);
        room.descriptionPublisher.receive(on: DispatchQueue.main).assign(to: \.text, on: roomSubjectField).store(in: &cancellables);
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "pencil.circle"), style: .plain, target: self, action: #selector(MucChatSettingsViewController.editClicked(_:)));
//        room.$affiliation.map({ $0 == .admin || $0 == .owner }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] value in
//            guard let that = self else {
//                return;
//            }
//            that.navigationItem.rightBarButtonItem = value ? UIBarButtonItem(barButtonSystemItem: .edit, target: that, action: #selector(MucChatSettingsViewController.editClicked(_:))) : nil;
//        }).store(in: &cancellables);
        pushNotificationsSwitch.isEnabled = false;
        pushNotificationsSwitch.isOn = false;
        room.optionsPublisher.map({ $0.encryption?.description ?? NSLocalizedString("Default", comment: "encryption setting value") }).receive(on: DispatchQueue.main).assign(to: \.text, on: encryptionField).store(in: &cancellables);
        room.optionsPublisher.map({ MucChatSettingsViewController.labelFor(conversationNotification: $0.notifications) }).receive(on: DispatchQueue.main).assign(to: \.text, on: notificationsField).store(in: &cancellables);
        refresh();
        
        if #available(iOS 14.0, *) {
            if let pepBookmarksModule = room.context?.module(.pepBookmarks) {
                room.$affiliation.map({ $0 == .admin || $0 == .owner }).combineLatest($canEditVCard, pepBookmarksModule.$currentBookmarks).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (value, canEditVCard, bookmarks) in
                    guard let that = self else {
                        return;
                    }
                    
                    that.navigationItem.rightBarButtonItem?.target = nil;
                    that.navigationItem.rightBarButtonItem?.action = nil;
                    that.navigationItem.rightBarButtonItem?.primaryAction = nil
                    that.navigationItem.rightBarButtonItem?.menu = that.prepareEditContextMenu(isOwner: value, canEditVCard: canEditVCard, bookmarks: bookmarks);
                }).store(in: &cancellables);
            }
        }
    }
    
    @available(iOS 14.0, *)
    private func prepareEditContextMenu(isOwner: Bool, canEditVCard: Bool, bookmarks: Bookmarks) -> UIMenu {
        var actions: [UIMenuElement] = [];
        
        if let pepBookmarksModule = room.context?.module(.pepBookmarks), let room = self.room, room.context?.isConnected ?? false {
            if let bookmark = bookmarks.conference(for: JID(room.jid)) {
                actions.append(UIAction(title: NSLocalizedString("Remove bookmark", comment: "button label"), image: UIImage(systemName: "bookmark.slash"), handler: { action in
                    pepBookmarksModule.remove(bookmark: bookmark);
                }));
            } else {
                actions.append(UIAction(title: NSLocalizedString("Create bookmark", comment: "button label"), image: UIImage(systemName: "bookmark"), handler: { action in
                    pepBookmarksModule.addOrUpdate(bookmark: Bookmarks.Conference(name: room.name ?? room.jid.localPart ?? room.jid.stringValue, jid: JID(room.jid), autojoin: false, nick: room.nickname, password: room.password));
                }));
            }
        }

        actions.append(UIAction(title: NSLocalizedString("Rename chat", comment: "button label"), handler: { action in
            self.renameChat();
        }));
        
        if canEditVCard {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                actions.append(UIMenu(title: NSLocalizedString("Change avatar", comment: "button label"), children: [
                    UIAction(title: NSLocalizedString("Take photo", comment: "button label"), handler: { action in
                        self.selectPhoto(.camera);
                    }),
                    UIAction(title: NSLocalizedString("Select photo", comment: "button label"), handler: { action in
                        self.selectPhoto(.photoLibrary);
                    })
                ]));
            } else {
                actions.append(UIAction(title: NSLocalizedString("Change avatar", comment: "button label"), handler: { action in
                    self.selectPhoto(.photoLibrary);
                }));
            }
        }
        
        actions.append(UIAction(title: NSLocalizedString("Change subject", comment: "button label"), handler: { action in
            self.changeSubject();
        }));
        
        return UIMenu(title: "", children: actions);
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        cancellables.removeAll();
        super.viewDidDisappear(animated);
    }
    
    @objc func dismissView() {
        self.dismiss(animated: true, completion: nil);
    }
    
    func refresh() {
        guard room.state == .joined, let context = room.context else {
            return;
        }
        showIndicator();
        
        let dispatchGroup = DispatchGroup();
        dispatchGroup.enter();
        context.module(.disco).getInfo(for: JID(room.jid), completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self.pushNotificationsSwitch.isEnabled = (context.module(.push) as! SiskinPushNotificationsModule).isEnabled && info.features.contains("jabber:iq:register");
                    if self.pushNotificationsSwitch.isEnabled {
                        self.room.checkTigasePushNotificationRegistrationStatus(completionHandler: { (result) in
                            switch result {
                            case .failure(_):
                                DispatchQueue.main.async {
                                    self.pushNotificationsSwitch.isEnabled = false;
                                    dispatchGroup.leave();
                                }
                            case .success(let value):
                                DispatchQueue.main.async {
                                    self.pushNotificationsSwitch.isOn = value;
                                    dispatchGroup.leave();
                                }
                            }
                        })
                    } else {
                        dispatchGroup.leave();
                    }
                case .failure(_):
                    self.pushNotificationsSwitch.isEnabled = false;
                    dispatchGroup.leave();
                }
            }
        });
        dispatchGroup.enter();
        context.module(.vcardTemp).retrieveVCard(from: JID(room.jid), completionHandler: { (result) in
            switch result {
            case .success(let vcard):
                DBVCardStore.instance.updateVCard(for: self.room.roomJid, on: self.room.account, vcard: vcard);
                DispatchQueue.main.async {
                    self.canEditVCard = true;
                    dispatchGroup.leave();
                }
            case .failure(_):
                DispatchQueue.main.async {
                    self.canEditVCard = false;
                    dispatchGroup.leave();
                }
            }
        })
        
        dispatchGroup.notify(queue: DispatchQueue.main, execute: self.hideIndicator);
    }
    
    @IBAction func pushNotificationSwitchChanged(_ sender: UISwitch) {
        self.room.registerForTigasePushNotification(sender.isOn) { (result) in
            switch result {
            case .failure(_):
                DispatchQueue.main.async {
                    sender.isOn = !sender.isOn;
                }
            case .success(_):
                // nothing to do..
                break;
            }
        }
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
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 2 && indexPath.row == 1 && !room.features.contains(.omemo) {
            return 0;
        }
        return super.tableView(tableView, heightForRowAt: indexPath);
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        if indexPath.section == 2 {
            if indexPath.row == 0 {
                let controller = TablePickerViewController<ConversationNotification>(options: [.always, .mention, .none], value: room.notifications, labelFn: MucChatSettingsViewController.labelFor(conversationNotification: ));
                controller.sink(receiveValue: { [weak self] value in
                    guard let room = self?.room else {
                        return;
                    }
                    room.updateOptions({ (options) in
                        options.notifications = value;
                    }, completionHandler: {
                        if let pushModule = (room.context?.module(.push) as? SiskinPushNotificationsModule), let pushSettings = pushModule.pushSettings {
                            pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                                switch result {
                                case .success(_):
                                    break;
                                case .failure(_):
                                    AccountSettings.pushHash(for: room.account, value: 0);
                                }
                            });
                        }
                    });
                });
                self.navigationController?.pushViewController(controller, animated: true);
            }
            if indexPath.row == 1 {
                let controller = TablePickerViewController<ConversationEncryption>(options: [.none, .omemo], value: room.options.encryption ?? .none);
                controller.sink(receiveValue: { value in
                    self.room.updateOptions({ (options) in
                        options.encryption = value;
                    }, completionHandler: nil);
                });
                self.navigationController?.pushViewController(controller, animated: true);
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "chatShowAttachments" {
            if let attachmentsController = segue.destination as? ChatAttachmentsController {
                attachmentsController.conversation = self.room;
            }
        }
    }
    
    @objc func editClicked(_ sender: UIBarButtonItem) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
        if room.context?.isConnected ?? false, let pepBookmarksModule = room.context?.module(.pepBookmarks) {
            if pepBookmarksModule.currentBookmarks.conference(for: JID(room.jid)) == nil {
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Create bookmark", comment: "button label"), style: .default, handler: { action in
                    pepBookmarksModule.addOrUpdate(bookmark: Bookmarks.Conference(name: self.room.name, jid: JID(self.room.jid), autojoin: false, nick: self.room.nickname, password: self.room.password));
                }))
            } else {
                alertController.addAction(UIAlertAction(title: NSLocalizedString("Remove bookmark", comment: "button label"), style: .default, handler: { action in
                    pepBookmarksModule.remove(bookmark: Bookmarks.Conference(name: self.room.name, jid: JID(self.room.jid), autojoin: false));
                }))
            }
        }
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Rename chat", comment: "button label"), style: .default, handler: { (action) in
            self.renameChat();
        }));
        if canEditVCard {
            alertController.addAction(UIAlertAction(title: NSLocalizedString("Change avatar", comment: "button label"), style: .default, handler: { (action) in
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Take photo", comment: "button label"), style: .default, handler: { (action) in
                        self.selectPhoto(.camera);
                    }));
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Select photo", comment: "button label"), style: .default, handler: { (action) in
                        self.selectPhoto(.photoLibrary);
                    }));
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
                    alert.popoverPresentationController?.barButtonItem = sender;
                    self.present(alert, animated: true, completion: nil);
                } else {
                    self.selectPhoto(.photoLibrary);
                }
            }));
        }
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Change subject", comment: "button label"), style: .default, handler: { (action) in
            self.changeSubject();
        }));
        alertController.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        alertController.popoverPresentationController?.barButtonItem = sender;
        self.present(alertController, animated: true, completion: nil);
    }
    
    private func selectPhoto(_ source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController();
        picker.delegate = self;
        picker.allowsEditing = true;
        picker.sourceType = source;
        present(picker, animated: true, completion: nil);
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard var photo = (info[UIImagePickerController.InfoKey.editedImage] as? UIImage) else {
            return;
        }
        
        self.showIndicator();
        // scalling photo to max of 180px
        var size: CGSize! = nil;
        if photo.size.height > photo.size.width {
            size = CGSize(width: (photo.size.width/photo.size.height) * 180, height: 180);
        } else {
            size = CGSize(width: 180, height: (photo.size.height/photo.size.width) * 180);
        }
        UIGraphicsBeginImageContextWithOptions(size, false, 0);
        photo.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height));
        photo = UIGraphicsGetImageFromCurrentImageContext()!;
        UIGraphicsEndImageContext();
        
        // saving photo
        guard let data = photo.jpegData(compressionQuality: 0.8) else {
            self.hideIndicator();
            return;
        }
        
        picker.dismiss(animated: true, completion: nil);

        guard let vcardTempModule = room.context?.module(.vcardTemp) else {
            hideIndicator();
            return;
        }
        
        let vcard = VCard();
        vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: data.base64EncodedString(), types: [.home])];
        vcardTempModule.publishVCard(vcard, to: room.roomJid, completionHandler: { result in
            switch result {
            case .success(_):
                DispatchQueue.main.async {
                    self.roomAvatarView.image = self.squared(image: photo);
                    self.hideIndicator();
                }
            case .failure(let errorCondition):
                DispatchQueue.main.async {
                    self.hideIndicator();
                    self.showError(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not set group chat avatar. The server responded with an error: %@", comment: "alert body"), errorCondition.localizedDescription));
                }
            }
        });
    }
    
    private func renameChat() {
        let controller = UIAlertController(title: NSLocalizedString("Rename chat", comment: "alert title"), message: NSLocalizedString("Enter new name for group chat", comment: "alert body"), preferredStyle: .alert);
        controller.addTextField { (textField) in
            textField.text = self.room.name ?? "";
        }
        let nameField = controller.textFields![0];
        controller.addAction(UIAlertAction(title: NSLocalizedString("Rename", comment: "button label"), style: .default, handler: { (action) in
            let newName = nameField.text;
            guard let mucModule = self.room.context?.module(.muc) else {
                return;
            }
            self.showIndicator();
            mucModule.getRoomConfiguration(roomJid: JID(self.room.jid), completionHandler: { result in
                switch result {
                case .success(let form):
                    (form.getField(named: "muc#roomconfig_roomname") as? TextSingleField)?.value = newName;
                    mucModule.setRoomConfiguration(roomJid: JID(self.room.jid), configuration: form, completionHandler: { result in
                        DispatchQueue.main.async {
                            self.hideIndicator();
                            switch result {
                            case .success(_):
                                self.roomNameField.text = nameField.text;
                            case .failure(let error):
                                self.showError(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not rename group chat. The server responded with an error: %@", comment: "alert body"), error.localizedDescription))
                            }
                        }
                    });
                case .failure(let error):
                    self.hideIndicator();
                    self.showError(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Could not rename group chat. The server responded with an error: %@", comment: "alert body"), error.localizedDescription))
                }
            });
        }))
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        self.present(controller, animated: true, completion: nil);
    }
    
    private func changeSubject() {
        let controller = UIAlertController(title: NSLocalizedString("Change subject", comment: "alert title"), message: NSLocalizedString("Enter new subject for group chat", comment: "alert body"), preferredStyle: .alert);
        controller.addTextField { (textField) in
            textField.text = self.room.subject ?? "";
        }
        let subjectField = controller.textFields![0];
        controller.addAction(UIAlertAction(title: NSLocalizedString("Change", comment: "button label"), style: .default, handler: { [weak self] (action) in
            guard let room = self?.room, let mucModule = self?.room.context?.module(.muc) else {
                return;
            }
            mucModule.setRoomSubject(roomJid: room.roomJid, newSubject: subjectField.text);
            self?.roomSubjectField.text = subjectField.text;
        }));
        controller.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
        self.present(controller, animated: true, completion: nil);
    }
    
    private func showError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .cancel, handler: nil));
        self.present(alert, animated: true, completion: nil);
    }
    
    private func squared(image inImage: UIImage?) -> UIImage? {
        guard let image = inImage else {
            return nil;
        }
        let origSize = image.size;
        guard origSize.width != origSize.height else {
            return image;
        }
        
        let size = min(origSize.width, origSize.height);
        
        let x = origSize.width > origSize.height ? ((origSize.width - origSize.height)/2) : 0.0;
        let y = origSize.width > origSize.height ? 0.0 : ((origSize.height - origSize.width)/2);
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0);
        image.draw(in: CGRect(x: x * (-1.0), y: y * (-1.0), width: origSize.width, height: origSize.height));
        let squared = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return squared;
    }
    
    static func labelFor(conversationNotification type: ConversationNotification) -> String {
        switch type {
        case .none:
            return NSLocalizedString("Muted", comment: "conversation notifications status");
        case .mention:
            return NSLocalizedString("When mentioned", comment: "conversation notifications status");
        case .always:
            return NSLocalizedString("Always", comment: "conversation notifications status");
        }
    }

}
