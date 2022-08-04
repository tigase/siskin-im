//
// NewFeaturesDetector.swift
//
// Siskin IM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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

enum ServerFeature: String {
    case mam
    case push
    
    public static func from(info: DiscoveryModule.DiscoveryInfoResult) -> [ServerFeature] {
        return from(features: info.features);
    }
    
    public static func from(features: [String]) -> [ServerFeature] {
        var serverFeatures: [ServerFeature] = [];
        if features.contains(MessageArchiveManagementModule.MAM_XMLNS) || features.contains(MessageArchiveManagementModule.MAM2_XMLNS) {
            serverFeatures.append(.mam);
        }
        if features.contains(PushNotificationsModule.PUSH_NOTIFICATIONS_XMLNS) {
            serverFeatures.append(.push);
        }
        return serverFeatures;
    }
}

class NewFeaturesDetector: XmppServiceExtension {
    
    public static let instance = NewFeaturesDetector();
    
    private init() {}
    
    private struct QueueItem {
        let account: BareJID;
        let newFeatures: [ServerFeature];
        let features: [ServerFeature];
    }
    
    private let queue = DispatchQueue(label: "NewFeaturesDetector");
    private var actionsQueue: [QueueItem] = [];
    private var inProgress: Bool = false;
        
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        let account = client.userBareJid;
        client.module(.disco).$accountDiscoResult.receive(on: queue).filter({ !$0.features.isEmpty }).map({ ServerFeature.from(info: $0) }).sink(receiveValue: { [weak self] newFeatures in
            self?.newFeatures(newFeatures, for: account);
        }).store(in: &cancellables);
        client.module(.disco).$accountDiscoResult.receive(on: queue).filter({ $0.features.isEmpty && $0.identities.isEmpty }).sink(receiveValue: { [weak self] _ in
            self?.removeFeatures(for: account);
        }).store(in: &cancellables);
    }
    
    private func newFeatures(_ newFeatures: [ServerFeature], for account: BareJID) {
        let oldFeatures = AccountSettings.knownServerFeatures(for: account);
        let change = newFeatures.filter({ !oldFeatures.contains($0) });
        
        guard !change.isEmpty else {
            return;
        }

        self.removeFeatures(for: account);
        actionsQueue.append(.init(account: account, newFeatures: change, features: newFeatures));
        showNext();
    }
    
    private func removeFeatures(for account: BareJID) {
        actionsQueue.removeAll(where: { $0.account == account});
    }
    
    private var navController: UINavigationController?;
    
    func showNext(fromController: Bool = false) {
        DispatchQueue.main.async {
            guard UIApplication.shared.applicationState == .active else {
                self.navController?.dismiss(animated: true, completion: nil);
                self.navController = nil;
                return;
            }
            
            guard let item: QueueItem = self.queue.sync(execute: {
                guard !self.inProgress || fromController else {
                    return nil;
                }
            
                let it = self.actionsQueue.first;
                if it != nil {
                    self.actionsQueue.remove(at: 0);
                    self.inProgress = true;
                }
                return it;
            }) else {
                self.navController?.dismiss(animated: true, completion: nil);
                self.navController = nil;
                return;
            }
        
            guard let client = XmppService.instance.getClient(for: item.account) else {
                self.queue.sync {
                    self.inProgress = false;
                }
                self.showNext();
                return;
            }

            let next: ()->Void = {
                if let navController = self.ensureNavController() {
                    let controller = navController.visibleViewController as! SetAccountSettingsController;
                    controller.client = client;
                
                    if item.newFeatures.contains(.mam) {
                        controller.sections.append(.mamEnable);
                        controller.sections.append(.mamSyncInitial);
                    }
                
                    controller.completionHandler = {
                        AccountSettings.knownServerFeatures(for: item.account, value: item.features);
                    }
                    
                    controller.tableView.reloadData();
                } else {
                    self.queue.sync {
                        self.inProgress = false;
                    }
                }
            }
            
            if item.newFeatures.contains(.push) && Settings.enablePush == nil {
                self.showPushQuestion(completionHandler: item.newFeatures.count == 1 ? { self.showNext(fromController: true) } : next);
            } else {
                next();
            }
        }
    }
    
    private func ensureNavController() -> UINavigationController? {
        guard let navController = self.navController else {
            let navController = UIStoryboard(name: "Account", bundle: nil).instantiateViewController(withIdentifier: "SetAccountSettingsNavController") as! UINavigationController;
            self.navController = navController;
            navController.modalPresentationStyle = .pageSheet;
            visibleController()?.present(navController, animated: true, completion: nil);
            return self.navController;
        }
        return navController;
    }
    
    private func visibleController() -> UIViewController? {
        let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow });
        if let controller = window?.rootViewController {
            return visibleController(parent: controller);
        } else {
            return nil;
        }
    }
    
    private func visibleController(parent: UIViewController) -> UIViewController {
        guard let presented = parent.presentedViewController else {
            return parent;
        }
        
        if let navController = presented as? UINavigationController, let visible = navController.visibleViewController {
            return visibleController(parent: visible);
        }
        
        if let tabController = presented as? UITabBarController, let visible = tabController.selectedViewController {
            return visibleController(parent: visible);
        }
        
        return presented;
    }
    
    private func showPushQuestion(completionHandler: @escaping ()->Void) {
        let alert = UIAlertController(title: NSLocalizedString("Push Notifications", comment: "alert title"), message: NSLocalizedString("If enabled, you will receive notifications of new messages or calls even if SiskinIM is in background. SiskinIM servers will forward those notifications for you from XMPP servers.", comment: "alert body"), preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("Enable", comment: "button label"), style: .default, handler: { _ in
            Settings.enablePush = true;
            completionHandler();
        }));
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
            Settings.enablePush = false;
            completionHandler();
        }))
        visibleController()?.present(alert, animated: true, completion: nil);
    }
    
}
