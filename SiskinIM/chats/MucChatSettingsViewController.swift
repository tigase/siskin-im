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
import TigaseSwift

class MucChatSettingsViewController: CustomTableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet var roomNameField: UILabel!;
    @IBOutlet var roomAvatarView: AvatarView!
    @IBOutlet var roomSubjectField: UILabel!;
    @IBOutlet var pushNotificationsSwitch: UISwitch!;
    @IBOutlet var notificationsField: UILabel!;
        
    fileprivate var activityIndicator: UIActivityIndicatorView?;
    
    var account: BareJID!;
    var room: DBRoom!;
    
    private var canEditVCard: Bool = false;
    
    override func viewWillAppear(_ animated: Bool) {
        view.backgroundColor = Appearance.current.secondarySystemBackground;
        roomNameField.text = room.name ?? "";
        roomAvatarView.layer.cornerRadius = roomAvatarView.frame.width / 2;
        roomAvatarView.layer.masksToBounds = true;
//        roomAvatarView.widthAnchor.constraint(equalTo: roomAvatarView.heightAnchor).isActive = true;
        roomAvatarView.set(name: nil, avatar: self.squared(image: AvatarManager.instance.avatar(for: room.roomJid, on: account)), orDefault: AvatarManager.instance.defaultGroupchatAvatar);
        roomSubjectField.text = room.subject ?? "";
        pushNotificationsSwitch.isEnabled = false;
        pushNotificationsSwitch.isOn = false;
        
        refresh();
        refreshPermissions();
    }
    
    @objc func dismissView() {
        self.dismiss(animated: true, completion: nil);
    }
    
    func refresh() {
        notificationsField.text = NotificationItem(type: room.options.notifications).description;
        
        guard let client = XmppService.instance.getClient(forJid: account), let discoveryModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID), let vcardTempModule: VCardTempModule = client.modulesManager.getModule(VCardTempModule.ID) else {
            return;
        }
        showIndicator();
        
        let dispatchGroup = DispatchGroup();
        dispatchGroup.enter();
        discoveryModule.getInfo(for: room.jid, onInfoReceived: { (node, identities, features) in
            DispatchQueue.main.async {
                let pushModule: SiskinPushNotificationsModule? = client.modulesManager.getModule(SiskinPushNotificationsModule.ID);
                self.pushNotificationsSwitch.isEnabled = (pushModule?.isEnabled ?? false) && features.contains("jabber:iq:register");
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
            }
        }, onError: { error in
            DispatchQueue.main.async {
                self.pushNotificationsSwitch.isEnabled = false;
                dispatchGroup.leave();
            }
        })
        dispatchGroup.enter();
        vcardTempModule.retrieveVCard(from: room.jid, onSuccess: { (vcard) in
            XmppService.instance.dbVCardsCache.updateVCard(for: self.room.roomJid, on: self.account, vcard: vcard);
            DispatchQueue.main.async {
                self.canEditVCard = true;
                dispatchGroup.leave();
            }
        }, onError: { errorCondition in
            DispatchQueue.main.async {
                self.canEditVCard = false;
                dispatchGroup.leave();
            }
        })
        
        dispatchGroup.notify(queue: DispatchQueue.main, execute: self.hideIndicator);
    }
    
    func refreshPermissions() {
        let presence = self.room.presences[self.room.nickname];
        let currentAffiliation = presence?.affiliation ?? .none;
        
        if currentAffiliation == .admin || currentAffiliation == .owner {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(editClicked(_:)));
        } else {
            self.navigationItem.rightBarButtonItem = nil;
        }
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
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        
        if indexPath.section == 2 && indexPath.row == 0 {
            let controller = TablePickerViewController();
            controller.items = [NotificationItem(type: .always), NotificationItem(type: .mention), NotificationItem(type: .none)];
            controller.selected = controller.items.firstIndex(where: { (item) -> Bool in
                return (item as! NotificationItem).type == room.options.notifications;
            })!;
            controller.onSelectionChange = { item in
                self.notificationsField.text = item.description;
                
                self.room.modifyOptions({ (options) in
                    options.notifications = (item as! NotificationItem).type;
                })
                let account = self.room.account;
                if let pushModule: SiskinPushNotificationsModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(SiskinPushNotificationsModule.ID), let pushSettings = pushModule.pushSettings {
                    pushModule.reenable(pushSettings: pushSettings, completionHandler: { result in
                        switch result {
                        case .success(_):
                            break;
                        case .failure(let err):
                            AccountSettings.pushHash(account).set(int: 0);
                        }
                    });
                }
            }
            self.navigationController?.pushViewController(controller, animated: true);
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "chatShowAttachments" {
            if let attachmentsController = segue.destination as? ChatAttachmentsController {
                attachmentsController.account = self.account;
                attachmentsController.jid = self.room.roomJid;
            }
        }
    }
    
    @objc func editClicked(_ sender: UIBarButtonItem) {
        let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
        alertController.addAction(UIAlertAction(title: "Rename chat", style: .default, handler: { (action) in
            self.renameChat();
        }));
        if canEditVCard {
            alertController.addAction(UIAlertAction(title: "Change avatar", style: .default, handler: { (action) in
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet);
                    alert.addAction(UIAlertAction(title: "Take photo", style: .default, handler: { (action) in
                        self.selectPhoto(.camera);
                    }));
                    alert.addAction(UIAlertAction(title: "Select photo", style: .default, handler: { (action) in
                        self.selectPhoto(.photoLibrary);
                    }));
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
                    alert.popoverPresentationController?.barButtonItem = sender;
                    self.present(alert, animated: true, completion: nil);
                } else {
                    self.selectPhoto(.photoLibrary);
                }
            }));
        }
        alertController.addAction(UIAlertAction(title: "Change subject", style: .default, handler: { (action) in
            self.changeSubject();
        }));
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
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
            print("no image available!");
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

        guard let vcardTempModule: VCardTempModule = XmppService.instance.getClient(for: room.account)?.modulesManager.getModule(VCardTempModule.ID) else {
            hideIndicator();
            return;
        }
        
        let vcard = VCard();
        vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: data.base64EncodedString(), types: [.home])];
        vcardTempModule.publishVCard(vcard, to: room.roomJid, onSuccess: {
            DispatchQueue.main.async {
                self.roomAvatarView.image = self.squared(image: photo);
                self.hideIndicator();
            }
        }, onError: { errorCondition in
            DispatchQueue.main.async {
                self.hideIndicator();
                self.showError(title: "Error", message: "Could not set group chat avatar. The server responded with an error: \((errorCondition ?? ErrorCondition.undefined_condition).rawValue)");
            }
        });
    }
    
    private func renameChat() {
        let controller = UIAlertController(title: "Rename chat", message: "Enter new name for group chat", preferredStyle: .alert);
        controller.addTextField { (textField) in
            textField.text = self.room.name ?? "";
        }
        let nameField = controller.textFields![0];
        controller.addAction(UIAlertAction(title: "Rename", style: .default, handler: { (action) in
            let newName = nameField.text;
            guard let mucModule: MucModule = XmppService.instance.getClient(for: self.room.account)?.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            self.showIndicator();
            mucModule.getRoomConfiguration(roomJid: self.room.jid, onSuccess: { (form) in
                (form.getField(named: "muc#roomconfig_roomname") as? TextSingleField)?.value = newName;
                mucModule.setRoomConfiguration(roomJid: self.room.jid, configuration: form, onSuccess: {
                    DispatchQueue.main.async {
                        self.roomNameField.text = nameField.text;
                        self.hideIndicator();
                    }
                }, onError: { errorCondition in
                    DispatchQueue.main.async {
                        self.hideIndicator();
                        self.showError(title: "Error", message: "Could not rename group chat. The server responded with an error: \((errorCondition ?? ErrorCondition.undefined_condition).rawValue)")
                    }
                });
            }, onError: { errorCondition in
                DispatchQueue.main.async {
                    self.hideIndicator();
                    self.showError(title: "Error", message: "Could not rename group chat. The server responded with an error: \((errorCondition ?? ErrorCondition.undefined_condition).rawValue)")
                }
            })
        }))
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
        self.present(controller, animated: true, completion: nil);
    }
    
    private func changeSubject() {
        let controller = UIAlertController(title: "Change subject", message: "Enter new subject for group chat", preferredStyle: .alert);
        controller.addTextField { (textField) in
            textField.text = self.room.subject ?? "";
        }
        let subjectField = controller.textFields![0];
        controller.addAction(UIAlertAction(title: "Change", style: .default, handler: { (action) in
            guard let mucModule: MucModule = XmppService.instance.getClient(for: self.room.account)?.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            mucModule.setRoomSubject(roomJid: self.room.roomJid, newSubject: subjectField.text);
            self.roomSubjectField.text = subjectField.text;
        }));
        controller.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
        self.present(controller, animated: true, completion: nil);
    }
    
    private func showError(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
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
        
        print("x:", x, "y:", y, "size:", size, "orig:", origSize);
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), false, 0);
        image.draw(in: CGRect(x: x * (-1.0), y: y * (-1.0), width: origSize.width, height: origSize.height));
        let squared = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        return squared;
    }
    
    class NotificationItem: TablePickerViewItemsProtocol {
        
        let type: ConversationNotification;
        
        var description: String {
            get {
                switch type {
                case .none:
                    return "Muted";
                case .mention:
                    return "When mentioned";
                case .always:
                    return "Always";
                }
            }
        }
        
        init(type: ConversationNotification) {
            self.type = type;
        }
        
    }
}
