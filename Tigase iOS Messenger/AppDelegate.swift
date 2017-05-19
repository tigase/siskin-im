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
import TigaseSwift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var xmppService:XmppService!;
    var dbConnection:DBConnection!;
    var defaultKeepOnlineOnAwayTime = TimeInterval(3 * 60);
    var keepOnlineOnAwayTimer: TigaseSwift.Timer?;
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        Log.initialize();
        Settings.initialize();
        do {
            dbConnection = try DBConnection(dbFilename: "mobile_messenger1.db");
            let resourcePath = Bundle.main.resourcePath! + "/db-schema-1.0.0.sql";
            print("loading SQL from file", resourcePath);
            let dbSchema = try String(contentsOfFile: resourcePath, encoding: String.Encoding.utf8);
            print("loaded schema:", dbSchema);
            try dbConnection.execute(dbSchema);
        } catch {
            print("DB initialization error:", error);
            fatalError("Initialization of database failed!");
        }
        xmppService = XmppService(dbConnection: dbConnection);
        xmppService.updateXmppClientInstance();
        registerUserNotificationSettings(application: application);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.serverCertificateError), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.authenticationFailure), name: XmppService.AUTHENTICATION_FAILURE, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.presenceAuthorizationRequest), name: XmppService.PRESENCE_AUTHORIZATION_REQUEST, object: nil);
        updateApplicationIconBadgeNumber();
        
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
        
        let timeout = min(defaultKeepOnlineOnAwayTime, application.backgroundTimeRemaining - 8);
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
        // mark background task as ended
        application.endBackgroundTask(taskId);
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        xmppService.applicationState = .active;
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        xmppService.applicationState = .active;
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        print(NSDate(), "application terminated!")
    }

    func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
        updateApplicationIconBadgeNumber();
        print("notification clicked", notification.userInfo);
        if (notification.category == "ERROR") {
            guard let userInfo = notification.userInfo else {
                return;
            }
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
                let alert = UIAlertController(title: notification.alertTitle, message: notification.alertBody, preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler: nil));
                
                var topController = UIApplication.shared.keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.present(alert, animated: true, completion: nil);
            }
        }
        if notification.category == "SUBSCRIPTION_REQUEST", let userInfo = notification.userInfo {
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
        if notification.category == "MESSAGE", let userInfo = notification.userInfo {
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
    
    func application(_ application: UIApplication, didRegister notificationSettings: UIUserNotificationSettings) {
        if notificationSettings.types != .none {
            application.registerForRemoteNotifications()
        }
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
        let fetchStart = Date();
        if let account = JID(userInfo[AnyHashable("account")] as? String), let sender = JID(userInfo[AnyHashable("sender")] as? String) {
            if let body = userInfo[AnyHashable("body")] as? String {
                notifyNewMessage(account: account, sender: sender, body: body, type: "chat", data: userInfo);
            }
            print(Date(), "starting fetching data");
            xmppService.preformFetch(for: account.bareJid) {(result) in
                completionHandler(result);
                let fetchEnd = Date();
                let time = fetchEnd.timeIntervalSince(fetchStart);
                print(Date(), "fetched date in \(time) seconds with result = \(result)");
            };
        }
    }
    
    func registerUserNotificationSettings(application: UIApplication) {
        var settings = UIUserNotificationSettings(types: [UIUserNotificationType.alert, UIUserNotificationType.badge, UIUserNotificationType.sound], categories: nil);
        application.registerUserNotificationSettings(settings);
    }
    
    func notifyNewMessage(account: JID, sender: JID, body: String, type: String?, data userInfo: [AnyHashable:Any]) {
        guard userInfo["carbonAction"] == nil else {
            return;
        }
        
        var senderName:String? = nil;
        if let sessionObject = xmppService.getClient(forJid: account.bareJid)?.sessionObject {
            senderName = RosterModule.getRosterStore(sessionObject).get(for: sender.withoutResource)?.name;
        }
        if senderName == nil {
            senderName = sender.stringValue;
        }
        
        var alertBody: String?;
        switch (type ?? "chat") {
        case "muc":
            if body.contains(userInfo["roomNickname"] as! String) {
                alertBody = senderName! + " mentioned you";
            } else {
                return;
            }
        default:
            alertBody = body;
        }
        
        let userNotification = UILocalNotification();
        userNotification.alertTitle = "Received new message from \(senderName!)";
        userNotification.alertAction = "open";
        userNotification.alertBody = alertBody;
        userNotification.soundName = UILocalNotificationDefaultSoundName;
        //userNotification.applicationIconBadgeNumber = UIApplication.sharedApplication().applicationIconBadgeNumber + 1;
        userNotification.userInfo = ["account": account.stringValue, "sender": sender.bareJid.stringValue];
        userNotification.category = "MESSAGE";
        UIApplication.shared.presentLocalNotificationNow(userNotification);
    }
    
    func newMessage(_ notification: NSNotification) {
        let sender = notification.userInfo?["sender"] as? BareJID;
        let account = notification.userInfo?["account"] as? BareJID;
        let incoming:Bool = (notification.userInfo?["incoming"] as? Bool) ?? false;
        guard sender != nil && account != nil && incoming else {
            return;
        }
        
        if UIApplication.shared.applicationState != .active {
            notifyNewMessage(account: JID(account!), sender: JID(sender!), body: notification.userInfo!["body"] as! String, type: notification.userInfo?["type"] as? String, data: notification.userInfo!);
        }
        updateApplicationIconBadgeNumber();
    }
    
    func chatItemsUpdated(_ notification: NSNotification) {
        updateApplicationIconBadgeNumber();
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
        
        let userNotification = UILocalNotification();
        userNotification.alertAction = "fix";
        userNotification.alertBody = "Received presence subscription request from " + senderName!;
        userNotification.userInfo = ["sender": sender!.stringValue as NSString, "account": account!.stringValue as NSString, "senderName": senderName! as NSString];
        userNotification.category = "SUBSCRIPTION_REQUEST";
        
        UIApplication.shared.presentLocalNotificationNow(userNotification);
    }
    
    func updateApplicationIconBadgeNumber() {
        DispatchQueue.global(qos: .default).async {
            let unreadChats = self.xmppService.dbChatHistoryStore.countUnreadChats();
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = unreadChats;
            }
        }
    }
    
    func serverCertificateError(_ notification: NSNotification) {
        guard let certInfo = notification.userInfo else {
            return;
        }
        
        let account = BareJID(certInfo["account"] as! String);
        
        let userNotification = UILocalNotification();
        userNotification.alertAction = "fix";
        userNotification.alertBody = "Connection to server \(account.domain) failed";
        userNotification.userInfo = certInfo;
        userNotification.category = "ERROR";
        UIApplication.shared.presentLocalNotificationNow(userNotification);
    }
    
    func authenticationFailure(_ notification: NSNotification) {
        guard let info = notification.userInfo else {
            return;
        }
        
        let account = BareJID(info["account"] as! String);
        let type = info["auth-error-type"] as! String;
        
        let userNotification = UILocalNotification();
        userNotification.alertAction = "fix";
        userNotification.alertBody = "Authentication for account \(account) failed: \(type)";
        userNotification.userInfo = info;
        userNotification.category = "ERROR";
        UIApplication.shared.presentLocalNotificationNow(userNotification);
    }

    func hideSetupGuide() {
        self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController();
        (self.window?.rootViewController as? UISplitViewController)?.preferredDisplayMode = .allVisible;
    }
}

