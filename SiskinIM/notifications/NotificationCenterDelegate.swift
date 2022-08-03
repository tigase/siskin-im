//
// NotificationCenterDelegate.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import Shared
import WebRTC
import Martin
import UserNotifications
import TigaseLogging

class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationCenterDelegate");
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        switch NotificationCategory.from(identifier: notification.request.content.categoryIdentifier) {
        case .MESSAGE:
            let account = notification.request.content.userInfo["account"] as? String;
            let sender = notification.request.content.userInfo["sender"] as? String;
            if (AppDelegate.isChatVisible(account: account, with: sender) && XmppService.instance.applicationState == .active) {
                completionHandler([]);
            } else {
                completionHandler([.alert, .sound]);
            }
        default:
            completionHandler([.alert, .sound]);
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content;
         
        switch NotificationCategory.from(identifier: response.notification.request.content.categoryIdentifier) {
        case .ERROR:
            didReceive(error: content, withCompletionHandler: completionHandler);
        case .SUBSCRIPTION_REQUEST:
            didReceive(subscriptionRequest: content, withCompletionHandler: completionHandler);
        case .MUC_ROOM_INVITATION:
            didReceive(mucInvitation: content, withCompletionHandler: completionHandler);
        case .MESSAGE:
            didReceive(messageResponse: response, withCompletionHandler: completionHandler);
        case .CALL:
            didReceive(call: content, withCompletionHandler: completionHandler);
        case .UNSENT_MESSAGES:
            completionHandler();
        case .UNKNOWN:
            self.logger.error("received unknown notification category: \( response.notification.request.content.categoryIdentifier)");
            completionHandler();
        }
     }
    
    func topController() -> UIViewController? {
        var controler: UIViewController? = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController;
        while (controler?.presentedViewController != nil) {
            controler = controler?.presentedViewController;
        }
        
        return controler;
    }

    func didReceive(error content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = content.userInfo;
            if userInfo["cert-name"] != nil {
                let accountJid = BareJID(userInfo["account"] as! String);
                let alert = CertificateErrorAlert.create(domain: accountJid.domain, certName: userInfo["cert-name"] as! String, certHash: userInfo["cert-hash-sha1"] as! String, issuerName: userInfo["issuer-name"] as? String, issuerHash: userInfo["issuer-hash-sha1"] as? String, onAccept: {
                    guard var account = AccountManager.getAccount(for: accountJid) else {
                        return;
                    }
                    let certInfo = account.serverCertificate;
                    certInfo?.accepted = true;
                    account.serverCertificate = certInfo;
                    account.active = true;
                    AccountSettings.lastError(for: accountJid, value: nil);
                    do {
                        try AccountManager.save(account: account);
                    } catch {
                        let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to save account details: %@ Please try again later.", comment: "alert title body"), error.localizedDescription), preferredStyle: .alert);
                        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button lable"), style: .cancel, handler: nil));
                        self.topController()?.present(alert, animated: true, completion: nil);
                    }
                }, onDeny: nil);
                
                topController()?.present(alert, animated: true, completion: nil);
            }
            if let authError = userInfo["auth-error-type"] {
                let accountJid = BareJID(userInfo["account"] as! String);
                
                let alert = UIAlertController(title: NSLocalizedString("Authentication issue", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Authentication for account %@ failed: %@\nVerify provided account password.", comment: "alert title body"), accountJid.stringValue, String(describing: authError)), preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .cancel, handler: nil));
                
                topController()?.present(alert, animated: true, completion: nil);
            } else {
                let alert = UIAlertController(title: content.title, message: content.body, preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .cancel, handler: nil));
                                
                topController()?.present(alert, animated: true, completion: nil);
            }
        completionHandler();
    }
    
    func didReceive(subscriptionRequest content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = content.userInfo;
        let senderJid = BareJID(userInfo["sender"] as! String);
        let accountJid = BareJID(userInfo["account"] as! String);
        var senderName = userInfo["senderName"] as! String;
        if senderName != senderJid.stringValue {
            senderName = "\(senderName) (\(senderJid.stringValue))";
        }
        let alert = UIAlertController(title: NSLocalizedString("Subscription request", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Received presence subscription request from\n%@\non account %@", comment: "alert title body"), senderName, accountJid.stringValue), preferredStyle: .alert);
        alert.addAction(UIAlertAction(title: NSLocalizedString("Accept", comment: "button label"), style: .default, handler: {(action) in
            guard let client = XmppService.instance.getClient(for: accountJid) else {
                return;
            }
            let presenceModule = client.module(.presence);
            presenceModule.subscribed(by: JID(senderJid));
            let subscription = DBRosterStore.instance.item(for: client.context, jid: JID(senderJid))?.subscription ?? .none;
            guard !subscription.isTo else {
                return;
            }
            if Settings.autoSubscribeOnAcceptedSubscriptionRequest {
                presenceModule.subscribe(to: JID(senderJid));
            } else {
                let alert2 = UIAlertController(title: String.localizedStringWithFormat(NSLocalizedString("Subscribe to %@", comment: "alert title"), senderName), message: String.localizedStringWithFormat(NSLocalizedString("Do you wish to subscribe to \n%@\non account %@", comment: "alert body"), senderName, accountJid.stringValue), preferredStyle: .alert);
                alert2.addAction(UIAlertAction(title: NSLocalizedString("Accept", comment: "button label"), style: .default, handler: {(action) in
                    presenceModule.subscribe(to: JID(senderJid));
                }));
                alert2.addAction(UIAlertAction(title: NSLocalizedString("Reject", comment: "button label"), style: .destructive, handler: nil));
                
                self.topController()?.present(alert2, animated: true, completion: nil);
            }
        }));
        alert.addAction(UIAlertAction(title: NSLocalizedString("Reject", comment: "button label"), style: .destructive, handler: {(action) in
            guard let client = XmppService.instance.getClient(for: accountJid) else {
                return;
            }
            client.module(.presence).unsubscribed(by: JID(senderJid));
        }));
        if let blockingCommandModule = XmppService.instance.getClient(for: accountJid)?.module(.blockingCommand), blockingCommandModule.isAvailable {
            guard let client = XmppService.instance.getClient(for: accountJid) else {
                return;
            }
            if blockingCommandModule.isReportingSupported {
                alert.addAction(UIAlertAction(title: NSLocalizedString("Block and report", comment: "button label"), style: .destructive, handler: { action in
                    let alert2 = UIAlertController(title: String.localizedStringWithFormat(NSLocalizedString("Block and report", comment: "report user title"), senderJid.stringValue), message: String.localizedStringWithFormat(NSLocalizedString("The user %@ will be blocked. Should it be reported as well?", comment: "report user message"), senderJid.stringValue), preferredStyle: .alert)
                    alert2.addAction(UIAlertAction(title: NSLocalizedString("Report spam", comment: "report spam action"), style: .default, handler: { _ in
                        client.module(.presence).unsubscribed(by: JID(senderJid))
                        blockingCommandModule.block(jid: JID(senderJid), report: .init(cause: .spam), completionHandler: { result in });
                    }))
                    alert2.addAction(UIAlertAction(title: NSLocalizedString("Report abuse", comment: "report abuse action"), style: .default, handler: { _ in
                        client.module(.presence).unsubscribed(by: JID(senderJid))
                        blockingCommandModule.block(jid: JID(senderJid), report: .init(cause: .abuse), completionHandler: { result in });
                    }))
                    alert2.addAction(UIAlertAction(title: NSLocalizedString("Just block", comment: "report spam action"), style: .default, handler: { _ in
                        client.module(.presence).unsubscribed(by: JID(senderJid))
                        blockingCommandModule.block(jid: JID(senderJid), completionHandler: { result in });
                    }))
                    self.topController()?.present(alert2, animated: true, completion: nil);
                }))
            } else {
                alert.addAction(UIAlertAction(title: NSLocalizedString("Block", comment: "button label"), style: .destructive, handler: { action in
                    client.module(.presence).unsubscribed(by: JID(senderJid))
                    blockingCommandModule.block(jids: [JID(senderJid)], completionHandler: { result in });
                }));
            }
        }
        
        topController()?.present(alert, animated: true, completion: nil);
        completionHandler();
    }
    
    func didReceive(mucInvitation content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let account = BareJID(content.userInfo["account"] as? String), let roomJid: BareJID = BareJID(content.userInfo["roomJid"] as? String) else {
            return;
        }
                
        let password = content.userInfo["password"] as? String;
                
        let controller = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinViewController") as! ChannelJoinViewController;
    
        controller.client = XmppService.instance.getClient(for: account);
        controller.channelJid = roomJid;
        controller.componentType = .muc;
        controller.password = password;

        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: controller, action: #selector(ChannelJoinViewController.cancelClicked(_:)));
        
        let navController = UINavigationController(rootViewController: controller);
        navController.modalPresentationStyle = .formSheet;
        topController()?.present(navController, animated: true, completion: nil);
        completionHandler();
    }
    
    func didReceive(messageResponse response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo;
        guard let accountJid = BareJID(userInfo["account"] as? String) else {
            completionHandler();
            return;
        }
        
        guard let senderJid = BareJID(userInfo["sender"] as? String) else {
            NotificationManager.instance.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
            return;
        }

        if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            NotificationManager.instance.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
        } else {
            openChatView(on: accountJid, with: senderJid, completionHandler: completionHandler);
        }
    }
    
    private func openChatView(on account: BareJID, with jid: BareJID, completionHandler: @escaping ()->Void) {
        var topController = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController;
        while (topController?.presentedViewController != nil) {
            if let tmp = topController?.presentedViewController, tmp.modalPresentationStyle != .none {
                tmp.dismiss(animated: true, completion: {
                    self.openChatView(on: account, with: jid, completionHandler: completionHandler);
                });
                return;
            } else {
                topController = topController?.presentedViewController;
            }
        }
        
        if topController != nil {
            guard let conversation = DBChatStore.instance.conversation(for: account, with: jid), let controller = viewController(for: conversation) else {
                completionHandler();
                return;
            }
            
            let navigationController = controller;
            let destination = navigationController.visibleViewController ?? controller;
            
            if let baseChatViewController = destination as? BaseChatViewController {
                baseChatViewController.conversation = conversation;
            }
            destination.hidesBottomBarWhenPushed = true;
            
            if let chatController = AppDelegate.getChatController(visible: false), let navController = chatController.parent as? UINavigationController {
                navController.pushViewController(destination, animated: true);
                var viewControllers = navController.viewControllers;
                if !viewControllers.isEmpty {
                    var i = 0;
                    while viewControllers[i] != chatController {
                        i = i + 1;
                    }
                    while (!viewControllers.isEmpty) && i > 0 && viewControllers[i] != destination {
                        viewControllers.remove(at: i);
                        i = i - 1;
                    }
                    navController.viewControllers = viewControllers;
                }
            } else {
                topController!.showDetailViewController(controller, sender: self);
            }
        } else {
            self.logger.error("No top controller!");
        }
    }
    
    private func viewController(for item: Conversation) -> UINavigationController? {
        switch item {
        case is Room:
            return UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "RoomViewNavigationController") as? UINavigationController;
        case is Chat:
            return UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "ChatViewNavigationController") as? UINavigationController;
        case is Channel:
            return UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelViewNavigationController") as? UINavigationController;
        default:
            return nil;
        }
    }
    
    func didReceive(call content: UNNotificationContent, withCompletionHandler completionHandler: @escaping () -> Void) {
        #if targetEnvironment(simulator)
        #else
        let userInfo = content.userInfo;
        let senderName = userInfo["senderName"] as! String;
        let senderJid = JID(userInfo["sender"] as! String);
        let accountJid = BareJID(userInfo["account"] as! String);
        let sdp = userInfo["sdpOffer"] as! String;
        let sid = userInfo["sid"] as! String;
        
        if let session = JingleManager.instance.session(for: accountJid, with: senderJid, sid: sid) {
            // can still can be received!
            let alert = UIAlertController(title: NSLocalizedString("Incoming call", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Incoming call from %@", comment: "alert body"), senderName), preferredStyle: .alert);
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied, .restricted:
                break;
            default:
                break;
//                alert.addAction(UIAlertAction(title: "Video call", style: .default, handler: { action in
//                    // accept video
//                    VideoCallController.accept(session: session, sdpOffer: sdp, withAudio: true, withVideo: true, sender: topController!);
//                }))
            }
//            alert.addAction(UIAlertAction(title: "Audio call", style: .default, handler: { action in
//                VideoCallController.accept(session: session, sdpOffer: sdp, withAudio: true, withVideo: false, sender: topController!);
//            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Dismiss", comment: "button label"), style: .cancel, handler: { action in
                session.decline();
            }));
            topController()?.present(alert, animated: true, completion: nil);
        } else {
            // call missed...
            let alert = UIAlertController(title: NSLocalizedString("Missed call", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("Missed incoming call from %@", comment: "alert body"), senderName), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: nil));
            
            topController()?.present(alert, animated: true, completion: nil);
        }
        #endif
        completionHandler();
    }
}
