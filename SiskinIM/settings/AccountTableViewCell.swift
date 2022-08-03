//
// AccountTableViewCell.swift
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
import Combine

class AccountTableViewCell: UITableViewCell {

    @IBOutlet var avatarStatusView: AvatarStatusView!
    @IBOutlet var nameLabel: UILabel!
    @IBOutlet var descriptionLabel: UILabel!;

    private var cancellables: Set<AnyCancellable> = [];
    private var avatarObj: Avatar? {
        didSet {
            avatarObj?.avatarPublisher.receive(on: DispatchQueue.main).assign(to: \.avatar, on: avatarStatusView.avatarImageView).store(in: &cancellables);
        }
    }
    
    override var backgroundColor: UIColor? {
        get {
            return super.backgroundColor;
        }
        set {
            super.backgroundColor = newValue;
            avatarStatusView?.backgroundColor = newValue;
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    func set(account accountJid: BareJID) {
        cancellables.removeAll();
        avatarObj = AvatarManager.instance.avatarPublisher(for: .init(account: accountJid, jid: accountJid, mucNickname: nil));
        nameLabel.text = accountJid.stringValue;
        if let acc = AccountManager.getAccount(for: accountJid) {
            descriptionLabel.text = acc.nickname;
            if acc.active {
                avatarStatusView.statusImageView.isHidden = false;
                acc.state.map({ value -> Presence.Show? in
                    switch value {
                    case .connected(_):
                        return .online
                    case .connecting, .disconnecting:
                        return .xa
                    default:
                        return nil;
                    }
                }).receive(on: DispatchQueue.main).assign(to: \.status, on: avatarStatusView).store(in: &cancellables);
            } else {
                avatarStatusView.statusImageView.isHidden = true;
            }
        } else {
            avatarStatusView.statusImageView.isHidden = false;
            descriptionLabel.text = nil;
        }
    }
}
