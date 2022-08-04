//
// AvatarStatusView.swift
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

class AvatarStatusView: UIView {
    
    @IBOutlet var avatarImageView: AvatarView!
    @IBOutlet var statusImageView: UIImageView! {
        didSet {
            statusImageView.backgroundColor = self.backgroundColor;
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    var displayableId: DisplayableIdProtocol? {
        didSet {
            cancellables.removeAll();
            if let namePublisher = displayableId?.displayNamePublisher, let avatarPublisher = displayableId?.avatarPublisher {
                namePublisher.combineLatest(avatarPublisher).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] name, image in
                    self?.avatarImageView.set(name: name, avatar: image);
                }).store(in: &cancellables);
            }
            displayableId?.statusPublisher.map({ AvatarStatusView.getStatusImage($0) }).assign(to: \.image, on: statusImageView).store(in: &cancellables);
        }
    }
    
    override var backgroundColor: UIColor? {
        get {
            return super.backgroundColor;
        }
        set {
            super.backgroundColor = newValue;
            statusImageView?.backgroundColor = newValue;
        }
    }
    
    var status: Presence.Show? {
        didSet {
            statusImageView.image = AvatarStatusView.getStatusImage(status);
        }
    }
    
    /*
    // Only override drawRect: if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func drawRect(rect: CGRect) {
        // Drawing code
    }
    */

    override func awakeFromNib() {
        super.awakeFromNib();
        //avatarImageView.image = UIImage(named: "first");
        updateCornerRadius();
    }
    
    func set(name: String?, avatar: UIImage?) {
        self.avatarImageView.set(name: name, avatar: avatar);
    }
        
    static func getStatusImage(_ status: Presence.Show?) -> UIImage? {
        // default color as for offline contact
        var image:UIImage? = UIImage(systemName: "circle.fill")?.withTintColor(UIColor.systemGray, renderingMode: .alwaysOriginal)
        if status != nil {
            switch status! {
            case .chat:
                image = UIImage(systemName: "asterisk.circle.fill")?.withTintColor(UIColor.green, renderingMode: .alwaysOriginal);
            case .online:
                image = UIImage(systemName: "circle.fill")?.withTintColor(UIColor.systemGreen, renderingMode: .alwaysOriginal)
            case .away:
                image = UIImage(systemName: "clock.fill")?.withTintColor(UIColor.systemOrange, renderingMode: .alwaysOriginal);
            case .xa:
                image = UIImage(systemName: "ellipsis.circle.fill")?.withTintColor(UIColor.systemOrange, renderingMode: .alwaysOriginal)
            case .dnd:
                image = UIImage(systemName: "moon.circle.fill")?.withTintColor(UIColor.systemRed, renderingMode: .alwaysOriginal)
            }
        }
        return image;
    }
    
    override func layoutSubviews() {
        super.layoutSubviews();
        updateCornerRadius();
    }
    
    func updateCornerRadius() {
        avatarImageView.layer.masksToBounds = true;
        avatarImageView.layer.cornerRadius = self.frame.height / 2;
        statusImageView.layer.opacity = 1.0;
        statusImageView.layer.masksToBounds = true;
        statusImageView.layer.cornerRadius = self.statusImageView.frame.height / 2;
    }
    
}
