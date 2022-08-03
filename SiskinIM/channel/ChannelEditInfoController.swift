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
import Martin
import Combine

class ChannelEditInfoController: UITableViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var nameField: UITextField!;
    @IBOutlet var descriptionField: UITextField!;
    
    var channel: Channel!;
    
    private var avatar: [PEPUserAvatarModule.Avatar]?;
    private var infoData: ChannelInfo?;
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        avatarView.contentMode = .scaleAspectFill;
        channel.displayNamePublisher.map({ $0 as String? }).receive(on: DispatchQueue.main).assign(to: \.text, on: nameField).store(in: &cancellables);
        channel.avatarPublisher.map({ $0 ?? AvatarManager.instance.defaultGroupchatAvatar }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] avatar in
            self?.avatarView.set(name: nil, avatar: avatar);
        }).store(in: &cancellables);
        channel.descriptionPublisher.receive(on: DispatchQueue.main).assign(to: \.text, on: descriptionField).store(in: &cancellables);
        
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
        guard let mixModule = channel.context?.module(.mix), let avatarModule = channel.context?.module(.pepUserAvatar) else {
            return;
        }

        self.operationStarted(message: NSLocalizedString("Updating…", comment: "channel edit info operation"));
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
                        let alert = UIAlertController(title: NSLocalizedString("Could not update channel details", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Remote server returned an error: %@", comment: "alert body"), err.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
                        self?.present(alert, animated: true, completion: nil);
                    }
                }
                group.leave();
            })
        }
        if let avatar = self.avatar {
            group.enter();
            avatarModule.publishAvatar(at: channel.channelJid, avatar: avatar, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    break;
                case .failure(let err):
                    DispatchQueue.main.async {
                        error = true;
                        let alert = UIAlertController(title: NSLocalizedString("Could not update channel details", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Remote server returned an error: %@", comment: "alert body"), err.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
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
        guard let mixModule = channel.context?.module(.mix) else {
            return;
        }
        self.operationStarted(message: NSLocalizedString("Refreshing…", comment: "channel edit info operation"));
        mixModule.retrieveInfo(for: channel.channelJid, completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self?.infoData = info;
                    self?.nameField.text = info.name;
                    self?.descriptionField.text = info.description;
                case .failure(_):
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
        guard let image = (info[UIImagePickerController.InfoKey.editedImage] as? UIImage), let pngImage = image.scaled(maxWidthOrHeight: 48), let pngData = pngImage.pngData() else {
            return;
        }
        
        avatar = [.init(data: pngData, mimeType: "image/png", width: Int(pngImage.size.width), height: Int(pngImage.size.width))];
        
        if let jpegImage = image.scaled(maxWidthOrHeight: 256), let jpegData = jpegImage.jpegData(compressionQuality: 0.75) {
            if let items = avatar {
                avatar = [.init(data: jpegData, mimeType: "image/jpeg", width: Int(jpegImage.size.width), height: Int(jpegImage.size.height))] + items;
            }
        }
        
        picker.dismiss(animated: true, completion: nil);
        avatarView.contentMode = .scaleAspectFill;
        avatarView.image = image.scaled(maxWidthOrHeight: 256);
    }
}
