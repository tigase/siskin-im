//
// InvitationChatTableViewCell.swift
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

class InvitationChatTableViewCell: BaseChatTableViewCell {
    
    @IBOutlet var messageField: UILabel!;
    @IBOutlet var acceptButton: UIButton!;
 
    @IBOutlet var defBottomButtonConstraint: NSLayoutConstraint?;
    
    private var account: BareJID?;
    private var appendix: ChatInvitationAppendix?;
    
    private var buttonBottomContraint: NSLayoutConstraint?;
    
    func set(item: ConversationEntry, message: String?, appendix: ChatInvitationAppendix) {
        super.set(item: item);
        self.account = item.conversation.account;
        self.appendix = appendix;
        acceptButton.layer.borderWidth = 2.0;
        acceptButton.layer.borderColor = UIColor(named: "tintColor")?.cgColor;
        acceptButton.layer.cornerRadius = acceptButton.frame.height / 2;
        if item.state.direction == .incoming, let account = self.account, let channel = self.appendix?.channel {
            acceptButton.isHidden = DBChatStore.instance.conversation(for: account, with: channel) != nil;
        } else {
            acceptButton.isHidden = true;
        }
        if acceptButton.isHidden {
            if buttonBottomContraint == nil {
                buttonBottomContraint = self.stateView!.bottomAnchor.constraint(equalTo: self.messageField.bottomAnchor);
            }
            buttonBottomContraint?.priority = .required;
            defBottomButtonConstraint?.isActive = false;
            buttonBottomContraint?.isActive = true;
        } else {
            buttonBottomContraint?.isActive = false;
            defBottomButtonConstraint?.isActive = true;
        }
        self.messageField.text = message ?? String.localizedStringWithFormat(NSLocalizedString("Invitation to channel %@", comment: "conversation log invitation to channel label"), appendix.channel.stringValue);
    }
    
    var viewController: UIViewController? {
        var parent: UIResponder? = self;
        while parent != nil {
            parent = parent?.next;
            if let controller = parent as? UIViewController {
                return controller;
            }
        }
        return nil;
    }
    
    @IBAction func acceptClicked(_ sender: UIButton) {
        guard let account = self.account, let mixInvitation = appendix?.mixInvitation() else {
            return;
        }
        
        let controller = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinViewController") as! ChannelJoinViewController;
        controller.client = XmppService.instance.getClient(for: account);
        controller.componentType = .mix
        controller.mixInvitation = mixInvitation;
        
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: controller, action: #selector(ChannelJoinViewController.cancelClicked(_:)));
        
        let navitation = UINavigationController(rootViewController: controller);
        navitation.modalPresentationStyle = .formSheet;
        
        viewController?.present(navitation, animated: true, completion: nil);
    }
}
