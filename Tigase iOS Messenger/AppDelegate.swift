//
// AppDelegate.swift
//
// Tigase iOS Messenger
// Copyright (C) 2016 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import UIKit
import UserNotifications
import TigaseSwift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    var window: UIWindow?
    var xmppService:XmppService!;
    var dbConnection:DBConnection!;
    var defaultKeepOnlineOnAwayTime = TimeInterval(3 * 60);
    var keepOnlineOnAwayTimer: TigaseSwift.Timer?;
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Log.initialize();
        Settings.initialize();
        AccountSettings.initialize();
        do {
            dbConnection = try DBConnection(dbFilename: "mobile_messenger1.db");
            let resourcePath = Bundle.main.resourcePath! + "/db-schema-1.0.0.sql";
            print("loading SQL from file", resourcePath);
            let dbSchema = try String(contentsOfFile: resourcePath, encoding: String.Encoding.utf8);
            print("loaded schema:", dbSchema);
            try dbConnection.execute(dbSchema);
            do {
                try dbConnection.execute("select preview from chat_history");
            } catch {
                try dbConnection.execute("ALTER TABLE chat_history ADD COLUMN preview TEXT");
            }
            do {
                try dbConnection.execute("select error from chat_history");
            } catch {
                try dbConnection.execute("ALTER TABLE chat_history ADD COLUMN error TEXT;");
            }
            
            // deal with duplicated chats for the same bare jid
            print("looking for duplicated chats...");
            let duplicates: [(String, String, Int)] = try dbConnection.prepareStatement("select min(c.id) as id, c.account, c.jid from (select count(id) as count, account, jid from chats group by account, jid) x inner join chats c on c.account = x.account and c.jid = x.jid where count > 1 group by c.account, c.jid").query() { (cursor) -> (String, String, Int) in
                let account: String = cursor["account"]!;
                let jid: String = cursor["jid"]!;
                let id: Int = cursor["id"] ?? 0;
                print("account", account, "jid", jid, "id", id);
                return (account, jid, id);
            }
            print("found duplicates", duplicates);
            try duplicates.forEach({ (account, jid, idToLeave) in
                let removed = try dbConnection.prepareStatement("delete from chats where account = ? and jid = ? and id <> :id").scalar(account, jid, idToLeave);
                print("for account", account, "and jid", jid, "removed", removed, "duplicated chats");
            });
            print("duplicated chats cleanup finished!");
        } catch {
            print("DB initialization error:", error);
            fatalError("Initialization of database failed!");
        }
        xmppService = XmppService(dbConnection: dbConnection);
        xmppService.updateXmppClientInstance();
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            // sending notifications not granted!
        }
        UNUserNotificationCenter.current().delegate = self;
        application.registerForRemoteNotifications();
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.serverCertificateError), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.authenticationFailure), name: XmppService.AUTHENTICATION_FAILURE, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.presenceAuthorizationRequest), name: XmppService.PRESENCE_AUTHORIZATION_REQUEST, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.pushNotificationRegistrationFailed), name: Notification.Name("pushNotificationsRegistrationFailed"), object: nil);
        updateApplicationIconBadgeNumber(completionHandler: nil);
        
        application.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum);
        
        (self.window?.rootViewController as? UISplitViewController)?.preferredDisplayMode = .allVisible;
        if AccountManager.getAccounts().isEmpty {
            self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SetupViewController");
        }
        
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        xmppService.applicationState = .inactive;
        
        self.keepOnlineOnAwayTimer?.execute();
        self.keepOnlineOnAwayTimer = nil;
        
        var taskId = UIBackgroundTaskInvalid;
        taskId = application.beginBackgroundTask {
            print("keep online on away background task expired", taskId);
            self.applicationKeepOnlineOnAwayFinished(application, taskId: taskId);
        }
        
        let timeout = min(defaultKeepOnlineOnAwayTime, application.backgroundTimeRemaining - 15);
        print("keep online on away background task", taskId, "started at", NSDate(), "for", timeout, "s");
        
        self.keepOnlineOnAwayTimer = Timer(delayInSeconds: timeout, repeats: false, callback: {
            self.applicationKeepOnlineOnAwayFinished(application, taskId: taskId);
        });
    }

    func applicationKeepOnlineOnAwayFinished(_ application: UIApplication, taskId: UIBackgroundTaskIdentifier) {
        // make sure timer is cancelled
        self.keepOnlineOnAwayTimer?.cancel();
        self.keepOnlineOnAwayTimer = nil;
        print("keep online timer finished at", taskId, NSDate());
        if (self.xmppService.backgroundTaskFinished()) {
            _ = Timer(delayInSeconds: 6, repeats: false, callback: {
                print("finshed disconnection of push accounts", taskId);
                application.endBackgroundTask(taskId);
            });
        } else {
            // mark background task as ended
            application.endBackgroundTask(taskId);
        }
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        //xmppService.applicationState = .active;
        //self.keepOnlineOnAwayTimer?.execute();
        //self.keepOnlineOnAwayTimer = nil;
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        xmppService.applicationState = .active;
        self.keepOnlineOnAwayTimer?.execute();
        self.keepOnlineOnAwayTimer = nil;
        
        self.updateApplicationIconBadgeNumber(completionHandler: nil);
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        print(NSDate(), "application terminated!")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content;
        let userInfo = content.userInfo;
        if content.categoryIdentifier == "ERROR" {
            if userInfo["cert-name"] != nil {
                let accountJid = BareJID(userInfo["account"] as! String);
                let certName = userInfo["cert-name"] as! String;
                let certHash = userInfo["cert-hash-sha1"] as! String;
                let issuerName = userInfo["issuer-name"] as? String;
                let issuerHash = userInfo["issuer-hash-sha1"] as? String;
                let issuer = issuerName != nil ? "\nissued by\n\(issuerName!)\n with fingerprint\n\(issuerHash!)" : "";
                let alert = UIAlertController(title: "Certificate issue", message: "Server for domain \(accountJid.domain) provided invalid certificate for \(certName)\n with fingerprint\n\(certHash)\(issuer).\nDo you trust this certificate?", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil));
                alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: {(action) in
                    print("accepted certificate!");
                    guard let account = AccountManager.getAccount(forJid: accountJid.stringValue) else {
                        return;
                    }
                    var certInfo = account.serverCertificate;
                    certInfo?["accepted"] = true as NSObject;
                    account.serverCertificate = certInfo;
                    account.active = true;
                    AccountSettings.LastError(accountJid.stringValue).set(string: nil);
                    AccountManager.updateAccount(account);
                }));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            }
            if let authError = userInfo["auth-error-type"] {
                let accountJid = BareJID(userInfo["account"] as! String);
                
                let alert = UIAlertController(title: "Authentication issue", message: "Authentication for account \(accountJid) failed: \(authError)\nVerify provided account password.", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            } else {
                let alert = UIAlertController(title: content.title, message: content.body, preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            }
        }
        if content.categoryIdentifier == "SUBSCRIPTION_REQUEST" {
            let userInfo = content.userInfo;
            let senderJid = BareJID(userInfo["sender"] as! String);
            let accountJid = BareJID(userInfo["account"] as! String);
            var senderName = userInfo["senderName"] as! String;
            if senderName != senderJid.stringValue {
                senderName = "\(senderName) (\(senderJid.stringValue))";
            }
            let alert = UIAlertController(title: "Subscription request", message: "Received presence subscription request from\n\(senderName)\non account \(accountJid.stringValue)", preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: "Accept", style: .default, handler: {(action) in
                guard let presenceModule: PresenceModule = self.xmppService.getClient(forJid: accountJid)?.context.modulesManager.getModule(PresenceModule.ID) else {
                    return;
                }
                presenceModule.subscribed(by: JID(senderJid));
                if let sessionObject = self.xmppService.getClient(forJid: accountJid)?.context.sessionObject {
                    let subscription = RosterModule.getRosterStore(sessionObject).get(for: JID(senderJid))?.subscription ?? RosterItem.Subscription.none;
                    guard !subscription.isTo else {
                        return;
                    }
                }
                if (Settings.AutoSubscribeOnAcceptedSubscriptionRequest.getBool()) {
                    presenceModule.subscribe(to: JID(senderJid));
                } else {
                    let alert2 = UIAlertController(title: "Subscribe to " + senderName, message: "Do you wish to subscribe to \n\(senderName)\non account \(accountJid.stringValue)", preferredStyle: .alert);
                    alert2.addAction(UIAlertAction(title: "Accept", style: .default, handler: {(action) in
                        presenceModule.subscribe(to: JID(senderJid));
                    }));
                    alert2.addAction(UIAlertAction(title: "Reject", style: .destructive, handler: nil));
                    
                    var topController = UIApplication.shared.keyWindow?.rootViewController;
                    while (topController?.presentedViewController != nil) {
                        topController = topController?.presentedViewController;
                    }
                    
                    topController?.present(alert2, animated: true, completion: nil);
                }
            }));
            alert.addAction(UIAlertAction(title: "Reject", style: .destructive, handler: {(action) in
                guard let presenceModule: PresenceModule = self.xmppService.getClient(forJid: accountJid)?.context.modulesManager.getModule(PresenceModule.ID) else {
                    return;
                }
                presenceModule.unsubscribed(by: JID(senderJid));
            }));
            
            var topController = UIApplication.shared.keyWindow?.rootViewController;
            while (topController?.presentedViewController != nil) {
                topController = topController?.presentedViewController;
            }
            
            topController?.present(alert, animated: true, completion: nil);
        }
        if content.categoryIdentifier == "MESSAGE" {
            let senderJid = BareJID(userInfo["sender"] as! String);
            let accountJid = BareJID(userInfo["account"] as! String);
            
            var topController = UIApplication.shared.keyWindow?.rootViewController;
            while (topController?.presentedViewController != nil) {
                topController = topController?.presentedViewController;
            }
            
            if topController != nil {
                let controller = topController!.storyboard?.instantiateViewController(withIdentifier: "ChatViewNavigationController");
                let navigationController = controller as? UINavigationController;
                let destination = navigationController?.visibleViewController ?? controller;
                
                if let baseChatViewController = destination as? BaseChatViewController {
                    baseChatViewController.account = accountJid;
                    baseChatViewController.jid = JID(senderJid);
                }
                destination?.hidesBottomBarWhenPushed = true;
                
                topController!.showDetailViewController(controller!, sender: self);
            } else {
                print("No top controller!");
            }
        }
        
        completionHandler();
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.categoryIdentifier == "MESSAGE" {
            let account = notification.request.content.userInfo["account"] as? String;
            let sender = notification.request.content.userInfo["sender"] as? String;
            if (isChatVisible(account: account, with: sender) && xmppService.applicationState == .active) {
                completionHandler([]);
            } else {
                completionHandler([.alert, .sound]);
            }
        } else {
            completionHandler([.alert, .sound]);
        }
    }
    
    func isChatVisible(account: String?, with jid: String?) -> Bool {
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }
        print("top controller", topController);
        guard let splitViewController = topController as? UISplitViewController else {
            return false;
        }
        
        print("visible controllers", splitViewController.viewControllers);
        guard let selectedTabController = splitViewController.viewControllers.map({(controller) in controller as? UITabBarController }).filter({ (controller) -> Bool in
            controller != nil
        }).map({(controller) in controller! }).first?.selectedViewController else {
            return false;
        }
        
        print("selected tab controller", selectedTabController);
        var baseChatController: BaseChatViewController? = nil;
        if let navigationController = selectedTabController as? UINavigationController {
            if let presented = navigationController.viewControllers.last {
                print("presented", presented);
                baseChatController = presented as? BaseChatViewController;
            }
        } else {
            baseChatController = selectedTabController as? BaseChatViewController;
        }
        
        guard baseChatController != nil else {
            return false;
        }
        
        print("comparing", baseChatController!.account.stringValue, account, baseChatController!.jid.stringValue, jid);
        return (baseChatController!.account.stringValue == account) && (baseChatController!.jid.bareJid.stringValue == jid);
    }
    
    func application(_ application: UIApplication, performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let fetchStart = Date();
        print(Date(), "starting fetching data");
        xmppService.preformFetch({(result) in
            completionHandler(result);
            let fetchEnd = Date();
            let time = fetchEnd.timeIntervalSince(fetchStart);
            print(Date(), "fetched date in \(time) seconds with result = \(result)");
        });
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)});
        
        print("Device Token:", tokenString)
        Settings.DeviceToken.setValue(tokenString);
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register:", error);
        Settings.DeviceToken.setValue(nil);
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        print("Push notification received: \(userInfo)");
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("Push notification received with fetch request: \(userInfo)");
        //let fetchStart = Date();
        if let account = JID(userInfo[AnyHashable("account")] as? String), let unreadMessages = userInfo["unread-messages"] as? Int {
            if let sender = JID(userInfo[AnyHashable("sender")] as? String) {
                if let body = userInfo[AnyHashable("body")] as? String {
                    notifyNewMessage(account: account, sender: sender, body: body, type: "chat", data: userInfo, isPush: true) {
                        completionHandler(.newData);
                    }
                    return;
                }
            // what is the point of fetching data/offline messages here?
            // we should do this on user request!
//            print(Date(), "starting fetching data");
//            xmppService.preformFetch(for: account.bareJid) {(result) in
//                completionHandler(result);
//                let fetchEnd = Date();
//                let time = fetchEnd.timeIntervalSince(fetchStart);
//                print(Date(), "fetched date in \(time) seconds with result = \(result)");
//            };
            }
            else if unreadMessages == 0 {
                let state = self.xmppService.getClient(forJid: account.bareJid)?.state;
                print("unread messages retrieved, client state =", state);
                if state != .connected {
                    dismissPushNotifications(for: account) {
                        completionHandler(.newData);
                    }
                    return;
                }
            }
        }
        
        completionHandler(.newData);
    }
    
    func notifyNewMessage(account: JID, sender: JID, body: String, type: String?, data userInfo: [AnyHashable:Any], isPush: Bool, completionHandler: (()->Void)?) {
        guard userInfo["carbonAction"] == nil else {
            return;
        }
        
        var alertBody: String?;
        switch (type ?? "chat") {
        case "muc":
            guard body.contains(userInfo["roomNickname"] as! String), let nick = userInfo["senderName"] as? String else {
                return;
            }
            alertBody = "\(nick) mentioned you: \(body)";
        default:
            guard let sessionObject = xmppService.getClient(forJid: account.bareJid)?.sessionObject else {
                return;
            }
            
            if let senderRosterItem = RosterModule.getRosterStore(sessionObject).get(for: sender.withoutResource) {
                let senderName = senderRosterItem.name ?? sender.withoutResource.stringValue;
                alertBody = "\(senderName): \(body)";
            } else {
                guard Settings.NotificationsFromUnknown.getBool() else {
                    return;
                }
                alertBody = "Message from unknown: " + sender.withoutResource.stringValue;
            }
        }
        
        let threadId = "account=" + account.stringValue + "|sender=" + sender.bareJid.stringValue;
        
        let id = threadId + ":body=" + (body.characters.count > 400 ? body.substring(to: body.index(body.startIndex, offsetBy: 400)) : body);
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            if notifications.filter({(notification) in  notification.request.identifier == id}).isEmpty {
                let content = UNMutableNotificationContent();
                //content.title = "Received new message from \(senderName!)";
                content.body = alertBody!;
                content.sound = UNNotificationSound.default();
                content.userInfo = ["account": account.stringValue, "sender": sender.bareJid.stringValue, "push": isPush];
                content.categoryIdentifier = "MESSAGE";
                content.threadIdentifier = threadId;
                
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil), withCompletionHandler: {(error) in
                    print("message notification error", error);
                    self.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
                });
            }
        }
    }
    
    func newMessage(_ notification: NSNotification) {
        let sender = notification.userInfo?["sender"] as? BareJID;
        let account = notification.userInfo?["account"] as? BareJID;
        let incoming:Bool = (notification.userInfo?["incoming"] as? Bool) ?? false;
        let fromArchive: Bool = (notification.userInfo?["fromArchive"] as? Bool) ?? false;
        guard sender != nil && account != nil && incoming && !fromArchive else {
            return;
        }
        
        notifyNewMessage(account: JID(account!), sender: JID(sender!), body: notification.userInfo!["body"] as! String, type: notification.userInfo?["type"] as? String, data: notification.userInfo!, isPush: false, completionHandler: nil);
    }
    
    func dismissPushNotifications(for account: JID, completionHandler: (()-> Void)?) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let toRemove = notifications.filter({ (notification) in notification.request.content.categoryIdentifier == "MESSAGE" }).filter({ (notification) in (notification.request.content.userInfo["account"] as? String) == account.stringValue && (notification.request.content.userInfo["push"] as? Bool ?? false) }).map({ (notification) in notification.request.identifier });
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
            self.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
        }
    }
    
    func chatItemsUpdated(_ notification: NSNotification) {
        updateApplicationIconBadgeNumber(completionHandler: nil);
    }
    
    func presenceAuthorizationRequest(_ notification: NSNotification) {
        let sender = notification.userInfo?["sender"] as? BareJID;
        let account = notification.userInfo?["account"] as? BareJID;
        var senderName:String? = nil;
        if let sessionObject = xmppService.getClient(forJid: account!)?.sessionObject {
            senderName = RosterModule.getRosterStore(sessionObject).get(for: JID(sender!))?.name;
        }
        if senderName == nil {
            senderName = sender!.stringValue;
        }
        
        let content = UNMutableNotificationContent();
        content.body = "Received presence subscription request from " + senderName!;
        content.userInfo = ["sender": sender!.stringValue as NSString, "account": account!.stringValue as NSString, "senderName": senderName! as NSString];
        content.categoryIdentifier = "SUBSCRIPTION_REQUEST";
        content.threadIdentifier = "account=" + account!.stringValue + "|sender=" + sender!.stringValue;
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }
    
    func pushNotificationRegistrationFailed(_ notification: NSNotification) {
        let account = notification.userInfo?["account"] as? BareJID;
        let errorCondition = (notification.userInfo?["errorCondition"] as? ErrorCondition) ?? ErrorCondition.internal_server_error;
        let content = UNMutableNotificationContent();
        switch errorCondition {
        case .remote_server_timeout:
            content.body = "It was not possible to contact push notification component.\nTry again later."
        case .remote_server_not_found:
            content.body = "It was not possible to contact push notification component."
        case .service_unavailable:
            content.body = "Push notifications not available";
        default:
            content.body = "It was not possible to contact push notification component: \(errorCondition.rawValue)";
        }
        content.threadIdentifier = "account=" + account!.stringValue;
        content.categoryIdentifier = "ERROR";
        content.userInfo = ["account": account!.stringValue];
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }
    
    func updateApplicationIconBadgeNumber(completionHandler: (()->Void)?) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            var unreadChats = Set(notifications.filter({(notification) in notification.request.content.categoryIdentifier == "MESSAGE" }).map({ (notification) in
                return notification.request.content.threadIdentifier;
            }));
            self.dbConnection.dispatch_async_db_queue {
                self.xmppService.dbChatHistoryStore.forEachUnreadChat(forEach: { (account, jid) in
                    unreadChats.insert("account=" + account.stringValue + "|sender=" + jid.stringValue);
                });
                let badge = unreadChats.count;
                DispatchQueue.main.async {
                    print("setting badge to", badge);
                    UIApplication.shared.applicationIconBadgeNumber = badge;
                    completionHandler?();
                }
            }
        }
    }
    
    func serverCertificateError(_ notification: NSNotification) {
        guard let certInfo = notification.userInfo else {
            return;
        }
        
        let account = BareJID(certInfo["account"] as! String);
        
        let content = UNMutableNotificationContent();
        content.body = "Connection to server \(account.domain) failed";
        content.userInfo = certInfo;
        content.categoryIdentifier = "ERROR";
        content.threadIdentifier = "account=" + account.stringValue;
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }
    
    func authenticationFailure(_ notification: NSNotification) {
        guard let info = notification.userInfo else {
            return;
        }
        
        let account = BareJID(info["account"] as! String);
        let type = info["auth-error-type"] as! String;
        
        let content = UNMutableNotificationContent();
        content.body = "Authentication for account \(account) failed: \(type)";
        content.userInfo = info;
        content.categoryIdentifier = "ERROR";
        content.threadIdentifier = "account=" + account.stringValue;
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }

    func hideSetupGuide() {
        self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController();
        (self.window?.rootViewController as? UISplitViewController)?.preferredDisplayMode = .allVisible;
    }
    
}

