//
// AccountSelectionView.swift
//
// Siskin IM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

import SwiftUI
import Martin
import Shared

@available(iOS 14.0, *)
struct AccountSelectionView: View {
    
    public static func selectAccount(parentController: UIViewController, completionHandler: @escaping (BareJID) ->Void) {
        let accounts = AccountManager.activeAccounts().map({ $0.name }).sorted();
        guard accounts.count != 1 else {
            if let account = accounts.first {
                completionHandler(account);
            }
            return;
        }
        let controller = UINavigationController(rootViewController: UIHostingController(rootView: AccountSelectionView(accounts: accounts, selection: { account in
            parentController.presentedViewController?.dismiss(animated: true, completion: {
                completionHandler(account);
            });
        })));
        controller.visibleViewController?.title = NSLocalizedString("Select account", comment: "ask user to select acount")
        controller.visibleViewController?.navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction(handler: { action in
            controller.dismiss(animated: true);
        }));
        controller.modalPresentationStyle = .formSheet;
        if #available(iOS 15.0, *), let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium()];
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false;
        }
        parentController.present(controller, animated: true)
    }
    
    var accounts: [BareJID] = []
    var selection: ((BareJID)->Void)?
    
    var body: some View {
        VStack {
            Text(NSLocalizedString("Select account to open chat from", comment: "alert body")).font(.body)
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(accounts, id: \.description) { account in
                        AccountView(account: account, avatar: AvatarManager.instance.avatarPublisher(for: .init(account: account, jid: account, mucNickname: nil)))
                            .scaledToFill()
                            .onTapGesture {
                                selection?(account);
                            }
                    }
                }
                .padding(.all, 10)
                .scaledToFill()
            }
        }
    }
    
    struct AccountView: View {
        
        var account: BareJID = BareJID("")
        var avatar: Avatar;
        
        @State
        private var avatarImage: UIImage? = nil;
        var body: some View {
            HStack {
                Image(uiImage: avatarImage ?? AvatarManager.instance.defaultAvatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .onReceive(avatar, perform: { newAvatar in
                        self.avatarImage = newAvatar ?? .withInitials(AccountManager.account(for: account)?.nickname, size: .init(width: 36, height: 36)) ?? AvatarManager.instance.defaultAvatar;
                    })
                Text(account.description)
                    .font(.headline)
                    .scaledToFill()
            }
        }
        
    }
}

@available(iOS 14.0, *)
struct AccountSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        AccountSelectionView()
    }
}
