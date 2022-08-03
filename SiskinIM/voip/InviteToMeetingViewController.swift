//
// InviteToMeetingViewController.swift
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
import Martin

class InviteToMeetingViewController: MultiContactSelectionViewController {

    private var changeAccountButton: UIBarButtonItem!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    var meet: Meet?;
        
    override func viewDidLoad() {
        super.viewDidLoad();
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: "button label"), style: .plain, target: self, action: #selector(cancelTapped(_:)));
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Invite", comment: "button label"), style: .done, target: self, action: #selector(inviteTapped(_:)));

        $selectedItems.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] items in
            self?.navigationItem.rightBarButtonItem?.isEnabled = (self?.meet != nil) && !items.isEmpty;
        }).store(in: &cancellables);
    }
        
    @objc func inviteTapped(_ sender: Any) {
        guard let meet = self.meet else {
            return;
        }
        
        let participants = self.selectedItems.map({ $0.jid });
        guard !participants.isEmpty else {
            return;
        }
        
        meet.allow(jids: participants, completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let jids):
                    for jid in jids {
                        meet.client.module(.meet).sendMessageInitiation(action: .propose(id: UUID().uuidString, meetJid: JID(meet.jid), media: [.audio, .video]), to: JID(jid));
                    }
                    self.dismiss();
                case .failure(let error):
                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to grant selected users access to the meeting. Received an error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                        self.dismiss();
                    }))
                    self.present(alert, animated: true, completion: nil);
                }
            }
        });
    }

    @objc func cancelTapped(_ sender: Any) {
        dismiss();
    }
    
    private func dismiss() {
        self.navigationController?.dismiss(animated: true, completion: nil);
    }
    
}
