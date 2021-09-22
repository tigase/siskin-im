//
// ChatTableViewMarkerCell.swift
//
// Siskin IM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import Combine

class ChatTableViewMarkerCell: UITableViewCell {
    
    @IBOutlet var label: UILabel!;
    @IBOutlet var avatars: UIStackView!;
    private var cancellables: Set<AnyCancellable> = [];
    
    func set(item: ConversationEntry, type: ChatMarker.MarkerType, senders: [ConversationEntrySender]) {
        cancellables.removeAll();
        
        for view in self.avatars.arrangedSubviews {
            view.removeFromSuperview();
        }
        
        for idx in 0..<min(4, senders.count) {
            let view = AvatarView(frame: .init(x: 0, y: 0, width: 14, height: 14));
            view.clipsToBounds = true;
            NSLayoutConstraint.activate([view.heightAnchor.constraint(equalToConstant: 14), view.widthAnchor.constraint(equalToConstant: 14)]);
            view.scalesLargeContentImage = true;
            if let avatarPublisher = senders[idx].avatar(for: item.conversation)?.avatarPublisher {
                let name = senders[idx].nickname;
                avatarPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { avatar in
                    view.set(name: name, avatar: avatar);
                }).store(in: &cancellables);
            } else {
                view.set(name: senders[idx].nickname, avatar: nil);
            }
            self.avatars.addArrangedSubview(view);
        }
        self.avatars.arrangedSubviews.forEach({ $0.layoutSubviews() });
        
        let prefix = senders.count > 3 ? "+\(senders.count - 3) " : "";
        
        self.label?.text = "\(prefix)\(type.label)";
    }
    
    
}
