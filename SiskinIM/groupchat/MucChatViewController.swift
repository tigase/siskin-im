//
// MucChatViewController.swift
//
// Siskin IM
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
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
import MartinOMEMO
import Combine

class MucChatViewController: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar {

    static let MENTION_OCCUPANT = Notification.Name("groupchatMentionOccupant");
    
    var titleView: MucTitleView! {
        get {
            return self.navigationItem.titleView as? MucTitleView;
        }
    }
    var room: Room {
        return self.conversation as! Room;
    }

    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(MucChatViewController.roomInfoClicked));
        self.titleView?.isUserInteractionEnabled = true;
        self.navigationController?.navigationBar.addGestureRecognizer(recognizer);
        
        initializeSharing();
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        
        room.context!.$state.map({ $0 == .connected() }).combineLatest(room.$state).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (connected, state) in
            self?.titleView?.refresh(connected: connected, state: state);
            self?.navigationItem.rightBarButtonItem?.isEnabled = state == .joined;
        }).store(in: &cancellables);
        room.displayNamePublisher.map({ $0 }).assign(to: \.name, on: self.titleView).store(in: &cancellables);
    }

    override func viewDidDisappear(_ animated: Bool) {
        cancellables.removeAll();
        super.viewDidDisappear(animated);
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func canExecuteContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ConversationEntry, at indexPath: IndexPath) -> Bool {
        switch action {
        case .retract:
            return item.state.direction == .outgoing && room.context?.state == .connected() && room.state == .joined;
        default:
            return super.canExecuteContext(action: action, forItem: item, at: indexPath);
        }
    }
    
    override func executeContext(action: BaseChatViewControllerWithDataSourceAndContextMenuAndToolbar.ContextAction, forItem item: ConversationEntry, at indexPath: IndexPath) {
        switch action {
        case .retract:
            guard item.state.direction == .outgoing else {
                return;
            }
            
            room.retract(entry: item);
        default:
            super.executeContext(action: action, forItem: item, at: indexPath);
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showOccupants" {
            if let navigation = segue.destination as? UINavigationController {
                if let occupantsController = navigation.visibleViewController as? MucChatOccupantsTableViewController {
                    occupantsController.room = room;
                    occupantsController.mentionOccupant = { [weak self] name in
                        var text = self?.messageText ?? "";
                        if text.last != " " {
                            text = text + " ";
                        }
                        self?.messageText = "\(text)@\(name) ";
                    }
                }
            } else {
                if let occupantsController = segue.destination as? MucChatOccupantsTableViewController {
                    occupantsController.room = room;
                    occupantsController.mentionOccupant = { [weak self] name in
                        var text = self?.messageText ?? "";
                        if text.last != " " {
                            text = text + " ";
                        }
                        self?.messageText = "\(text)@\(name) ";
                    }
                }
            }
        }
        super.prepare(for: segue, sender: sender);
    }
    
    @IBAction func sendClicked(_ sender: UIButton) {
        self.sendMessage();
    }

    override func sendMessage() {
        guard let text = messageText, !text.isEmpty else {
            return;
        }
        
        guard room.state == .joined else {
            let alert = UIAlertController.init(title: NSLocalizedString("Warning", comment: "alert title"), message: NSLocalizedString("You are not connected to room.\nPlease wait reconnection to room", comment: "alert body"), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
            self.present(alert, animated: true, completion: nil);
            return;
        }
        
        let canEncrypt = room.features.contains(.omemo);
        
        let encryption: ChatEncryption = room.options.encryption ?? (canEncrypt ? Settings.messageEncryption : .none);
        guard encryption == .none || canEncrypt else {
            if encryption == .omemo && !canEncrypt {
                let alert = UIAlertController(title: NSLocalizedString("Warning", comment: "alert title"), message: NSLocalizedString("This room is not capable of sending encrypted messages. Please change encryption settings to be able to send messages", comment: "alert body"), preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                self.present(alert, animated: true, completion: nil);
            }
            return;
        }
        
        room.sendMessage(text: text, correctedMessageOriginId: correctedMessageOriginId);
        DispatchQueue.main.async {
            self.messageText = nil;
        }
    }
    
    override func sendAttachment(originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (() -> Void)?) {
        let canEncrypt = room.features.contains(.omemo);
        
        let encryption: ChatEncryption = room.options.encryption ?? (canEncrypt ? Settings.messageEncryption : .none);
        guard encryption == .none || canEncrypt else {
            completionHandler?();
            return;
        }
        
        room.sendAttachment(url: uploadedUrl, appendix: appendix, originalUrl: originalUrl, completionHandler: completionHandler);
    }
    
    @objc func roomInfoClicked() {
        guard let settingsController = self.storyboard?.instantiateViewController(withIdentifier: "MucChatSettingsViewController") as? MucChatSettingsViewController else {
            return;
        }
        settingsController.room = self.room;
        
        let navigation = UINavigationController(rootViewController: settingsController);
        navigation.title = self.title;
        navigation.modalPresentationStyle = .formSheet;
        settingsController.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: settingsController, action: #selector(MucChatSettingsViewController.dismissView));
        self.present(navigation, animated: true, completion: nil);
        //self.navigationController?.pushViewController(settingsController, animated: true);
    }

}

class MucTitleView: UIView {
    
    @IBOutlet var nameView: UILabel!;
    @IBOutlet var statusView: UILabel!;
    
    var name: String? {
        get {
            return nameView.text;
        }
        set {
            nameView.text = newValue;
        }
    }
    
    override var intrinsicContentSize: CGSize {
        return UIView.layoutFittingExpandedSize
    }
    
    override func didMoveToSuperview() {
        super.didMoveToSuperview();
        if let superview = self.superview {
            NSLayoutConstraint.activate([ self.widthAnchor.constraint(lessThanOrEqualTo: superview.widthAnchor, multiplier: 0.6)]);
        }
    }
    
    func refresh(connected: Bool, state: RoomState) {
        if connected {
            let statusIcon = NSTextAttachment();
            
            var show: Presence.Show?;
            var desc = NSLocalizedString("Offline", comment: "muc room status");
            switch state {
            case .joined:
                show = Presence.Show.online;
                desc = NSLocalizedString("Online", comment: "muc room status");
            case .requested:
                show = Presence.Show.away;
                desc = NSLocalizedString("Joining…", comment: "muc room status");
            default:
                break;
            }
            
            statusIcon.image = AvatarStatusView.getStatusImage(show);
            let height = statusView.font.pointSize;
            statusIcon.bounds = CGRect(x: 0, y: -2, width: height, height: height);
            
            let statusText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: statusIcon));
            statusText.append(NSAttributedString(string: desc));
            statusView.attributedText = statusText;
        } else {
            statusView.text = "\u{26A0} \(NSLocalizedString("Not connected", comment: "muc room status label"))!";
        }
    }
}
