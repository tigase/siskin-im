//
// ChannelEditInfoController.swift
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

class ChannelEditInfoController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var nameField: UITextField!;
    @IBOutlet var descriptionField: UITextField!;
    
    var channel: DBChannel!;
    
    private var avatarData: Data?;
    private var infoData: ChannelInfo?;
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        avatarView.set(name: nil, avatar: AvatarManager.instance.avatar(for: channel.channelJid, on: channel.account), orDefault: AvatarManager.instance.defaultGroupchatAvatar);
        nameField.text = channel.name;
        avatarView.contentMode = .scaleAspectFill;
        descriptionField.text = channel.description;
        
        refresh();
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.row == 0 && indexPath.section == 0 {
            selectPhoto(.photoLibrary);
            tableView.deselectRow(at: indexPath, animated: true);
        }
//        super.tableView(tableView, didSelectRowAt: indexPath);
    }
    
    @IBAction func saveClicked(_ sender: Any) {
        guard let client = XmppService.instance.getClient(for: channel.account), let mixModule: MixModule = client.modulesManager.getModule(MixModule.ID), let avatarModule: PEPUserAvatarModule = client.modulesManager.getModule(PEPUserAvatarModule.ID) else {
            return;
        }

        self.operationStarted(message: "Updating...");
        let group = DispatchGroup();
        var error: Bool = false;
        let infoData = ChannelInfo(name: nameField.text, description: descriptionField.text, contact: self.infoData?.contact ?? []);
        if let oldData = self.infoData, oldData.name != infoData.name || oldData.description != infoData.description {
            group.enter();
            mixModule.publishInfo(for: channel.channelJid, info: infoData, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    break;
                case .failure(let err):
                    DispatchQueue.main.async {
                        error = true;
                        let alert = UIAlertController(title: "Could not update channel details", message: "Remote server returned an error: \(err.rawValue)", preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }
                }
                group.leave();
            })
        }
        if let avatarData = self.avatarData {
            group.enter();
            avatarModule.publishAvatar(at: channel.channelJid, data: avatarData, mimeType: "image/jpeg", completionHandler: { [weak self] result in
                switch result {
                case .success(_, _, _):
                    break;
                case .failure(let errorCondition, _, _):
                    DispatchQueue.main.async {
                        error = true;
                        let alert = UIAlertController(title: "Could not update channel details", message: "Remote server returned an error: \(errorCondition.rawValue)", preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }
                }
                group.leave();
            })
        }
        group.notify(queue: DispatchQueue.main, execute: { [weak self] in
            self?.operationEnded();
            guard !error else {
                return;
            }
            self?.dismiss(animated: true, completion: nil)
        })
    }
    
    private func refresh() {
        guard let mixModule: MixModule = XmppService.instance.getClient(for: channel.account)?.modulesManager.getModule(MixModule.ID) else {
            return;
        }
        self.operationStarted(message: "Refreshing...");
        mixModule.retrieveInfo(for: channel.channelJid, completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self?.infoData = info;
                    self?.nameField.text = info.name;
                    self?.descriptionField.text = info.description;
                case .failure(let err):
                    self?.dismiss(animated: true, completion: nil);
                    break;
                }
                self?.operationEnded();
            }
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
    
    private func selectPhoto(_ source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController();
        picker.delegate = self;
        picker.allowsEditing = true;
        picker.sourceType = source;
        present(picker, animated: true, completion: nil);
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        guard let scaled = (info[UIImagePickerController.InfoKey.editedImage] as? UIImage)?.scaled(maxWidthOrHeight: 512.0), let data = scaled.jpegData(compressionQuality: 0.8) else {
            print("no image available!");
            return;
        }
        
        avatarData = data;
        
        picker.dismiss(animated: true, completion: nil);
        avatarView.contentMode = .scaleAspectFill;
        avatarView.image = scaled;
    }
}
