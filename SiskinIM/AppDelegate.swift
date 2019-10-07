//
// AppDelegate.swift
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
import UserNotifications
import TigaseSwift
//import CallKit
import WebRTC

extension DBConnection {
    
    static var main: DBConnection = {
        let conn = try! DBConnection(dbFilename: "mobile_messenger1.db");
        try! DBSchemaManager(dbConnection: conn).upgradeSchema();
        return conn;
    }();
    
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    var window: UIWindow?
    var xmppService:XmppService! {
        return XmppService.instance;
    }
    var dbConnection:DBConnection! {
        return DBConnection.main;
    }
//    var callProvider: CXProvider?;
    fileprivate var defaultKeepOnlineOnAwayTime = TimeInterval(3 * 60);
    fileprivate var keepOnlineOnAwayTimer: TigaseSwift.Timer?;
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        RTCInitFieldTrialDictionary([:]);
        RTCInitializeSSL();
        RTCSetupInternalTracer();
        Log.initialize();
        Settings.initialize();
        AccountSettings.initialize();
        Appearance.sync();
        xmppService.updateXmppClientInstance();
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            // sending notifications not granted!
        }
        UNUserNotificationCenter.current().delegate = self;
        application.registerForRemoteNotifications();
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.unreadMessagesCountChanged), name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.serverCertificateError), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.authenticationFailure), name: XmppService.AUTHENTICATION_FAILURE, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.presenceAuthorizationRequest), name: XmppService.PRESENCE_AUTHORIZATION_REQUEST, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.mucRoomInvitationReceived), name: XmppService.MUC_ROOM_INVITATION, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.pushNotificationRegistrationFailed), name: Notification.Name("pushNotificationsRegistrationFailed"), object: nil);
        updateApplicationIconBadgeNumber(completionHandler: nil);
        
        application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum);
        
        (self.window?.rootViewController as? UISplitViewController)?.preferredDisplayMode = .allVisible;
        if AccountManager.getAccounts().isEmpty {
            self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SetupViewController");
        }
        
//        let callConfig = CXProviderConfiguration(localizedName: "Tigase Messenger");
//        self.callProvider = CXProvider(configuration: callConfig);
//        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 5.0) {
//            let uuid = UUID();
//            let handle = CXHandle(type: CXHandle.HandleType.generic, value: "andrzej.wojcik@tigase.org");
//
//            let startCallAction = CXStartCallAction(call: uuid, handle: handle);
//            startCallAction.handle = handle;
//
//            let transaction = CXTransaction(action: startCallAction);
//            let callController = CXCallController();
//            callController.request(transaction, completion: { (error) in
//                CXErrorCodeRequestTransactionError.invalidAction
//                print("call request:", error?.localizedDescription);
//            })
//            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 30.0, execute: {
//                print("finished!", callController);
//            })
//        }
//
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
        
        var taskId = UIBackgroundTaskIdentifier.invalid;
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
        if #available(iOS 13.0, *) {
            Appearance.sync();
        }
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        //xmppService.applicationState = .active;
        //self.keepOnlineOnAwayTimer?.execute();
        //self.keepOnlineOnAwayTimer = nil;
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let toDiscard = notifications.filter({(notification) in  notification.request.content.categoryIdentifier == "MESSAGE_NO_SENDER" || notification.request.content.categoryIdentifier == "UNSENT_MESSAGES"}).map({ (notiication) -> String in
                return notiication.request.identifier;
            });
            guard !toDiscard.isEmpty else {
                return;
            }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toDiscard)
            self.updateApplicationIconBadgeNumber(completionHandler: nil);
        }
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
        RTCShutdownInternalTracer();
        RTCCleanupSSL();
        print(NSDate(), "application terminated!")
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false;
        }
        
        print("got url to open:", components);
        guard let xmppUri = XmppUri(url: url) else {
            return false;
        }
        print("got xmpp url with jid:", xmppUri.jid, "action:", xmppUri.action, "params:", xmppUri.dict);

        if let action = xmppUri.action {
            self.open(xmppUri: xmppUri, action: action);
            return true;
        } else {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Open URL", message: "What do you want to do with \(url)?", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "Open chat", style: .default, handler: { (action) in
                    self.open(xmppUri: xmppUri, action: .message);
                }))
                alert.addAction(UIAlertAction(title: "Join room", style: .default, handler: { (action) in
                    self.open(xmppUri: xmppUri, action: .join);
                }))
                alert.addAction(UIAlertAction(title: "Add contact", style: .default, handler: { (action) in
                    self.open(xmppUri: xmppUri, action: .roster);
                }))
                alert.addAction(UIAlertAction(title: "Nothing", style: .cancel, handler: nil));
                self.window?.rootViewController?.present(alert, animated: true, completion: nil);
            }
            return false;
        }
    }
    
    fileprivate func open(xmppUri: XmppUri, action: XmppUri.Action) {
        switch action {
        case .join:
            let navController = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "MucJoinNavigationController") as! UINavigationController;
            let newGroupchat = navController.visibleViewController as! MucJoinViewController;
            newGroupchat.xmppService = self.xmppService;
            newGroupchat.hidesBottomBarWhenPushed = true;
            navController.modalPresentationStyle = .formSheet;
            self.window?.rootViewController?.present(navController, animated: true, completion: {
                newGroupchat.serverTextField.text = xmppUri.jid.domain;
                newGroupchat.roomTextField.text = xmppUri.jid.localPart;
                newGroupchat.passwordTextField.text = xmppUri.dict?["password"];
            });
        case .message:
            let alert = UIAlertController(title: "Start chatting", message: "Select account to open chat from", preferredStyle: .alert);
            let accounts = self.xmppService.getClients().map({ (client) -> BareJID in
                return client.sessionObject.userBareJid!;
            }).sorted { (a1, a2) -> Bool in
                return a1.stringValue.compare(a2.stringValue) == .orderedAscending;
            }
            
            let openChatFn: (BareJID)->Void = { (account) in
                let xmppClient = self.xmppService.getClient(forJid: account);
                let messageModule:MessageModule? = xmppClient?.modulesManager.getModule(MessageModule.ID);
                
                guard messageModule != nil else {
                    return;
                }
                
                _ = messageModule!.chatManager!.getChatOrCreate(with: xmppUri.jid.withoutResource, thread: nil);
                
                guard let destination = self.window?.rootViewController?.storyboard?.instantiateViewController(withIdentifier: "ChatViewNavigationController") as? UINavigationController else {
                    return;
                }
                
                let chatController = destination.children[0] as! ChatViewController;
                chatController.hidesBottomBarWhenPushed = true;
                chatController.account = account;
                chatController.jid = xmppUri.jid.bareJid;
                self.window?.rootViewController?.showDetailViewController(destination, sender: self);
            }
            
            if accounts.count == 1 {
                openChatFn(accounts.first!);
            } else {
                accounts.forEach({ account in
                    alert.addAction(UIAlertAction(title: account.stringValue, style: .default, handler: { (action) in
                        openChatFn(account);
                    }));
                })
            
                self.window?.rootViewController?.present(alert, animated: true, completion: nil);
            }
        case .roster:
            guard let navigationController = self.window?.rootViewController?.storyboard?.instantiateViewController(withIdentifier: "RosterItemEditNavigationController") as? UINavigationController else {
                return;
            }
            let itemEditController = navigationController.visibleViewController as? RosterItemEditViewController;
            itemEditController?.hidesBottomBarWhenPushed = true;
            navigationController.modalPresentationStyle = .formSheet;
            self.window?.rootViewController?.present(navigationController, animated: true, completion: {
                itemEditController?.account = nil;
                itemEditController?.jid = xmppUri.jid;
                itemEditController?.jidTextField.text = xmppUri.jid.stringValue;
                itemEditController?.nameTextField.text = xmppUri.dict?["name"];
            });
        default:
            break;
        }
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content;
        let userInfo = content.userInfo;
        if content.categoryIdentifier == "ERROR" {
            if userInfo["cert-name"] != nil {
                let accountJid = BareJID(userInfo["account"] as! String);
                let alert = CertificateErrorAlert.create(domain: accountJid.domain, certName: userInfo["cert-name"] as! String, certHash: userInfo["cert-hash-sha1"] as! String, issuerName: userInfo["issuer-name"] as? String, issuerHash: userInfo["issuer-hash-sha1"] as? String, onAccept: {
                    print("accepted certificate!");
                    guard let account = AccountManager.getAccount(forJid: accountJid.stringValue) else {
                        return;
                    }
                    var certInfo = account.serverCertificate;
                    certInfo?["accepted"] = true as NSObject;
                    account.serverCertificate = certInfo;
                    account.active = true;
                    AccountSettings.LastError(accountJid).set(string: nil);
                    AccountManager.updateAccount(account);
                }, onDeny: nil);
                
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
        if content.categoryIdentifier == "MUC_ROOM_INVITATION" {
            guard let account = BareJID(content.userInfo["account"] as? String), let roomJid: BareJID = BareJID(content.userInfo["roomJid"] as? String) else {
                return;
            }
            
            let password = content.userInfo["password"] as? String;
            
            let navController = UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "MucJoinNavigationController") as! UINavigationController;

            let controller = navController.visibleViewController! as! MucJoinViewController;
            _ = controller.view;
            controller.accountTextField.text = account.stringValue;
            controller.roomTextField.text = roomJid.localPart;
            controller.serverTextField.text = roomJid.domain;
            controller.passwordTextField.text = password;
            
            var topController = UIApplication.shared.keyWindow?.rootViewController;
            while (topController?.presentedViewController != nil) {
                topController = topController?.presentedViewController;
            }
//            let navController = UINavigationController(rootViewController: controller);
            navController.modalPresentationStyle = .formSheet;
            topController?.present(navController, animated: true, completion: nil);
        }
        if content.categoryIdentifier == "MESSAGE" {
            let senderJid = BareJID(userInfo["sender"] as! String);
            let accountJid = BareJID(userInfo["account"] as! String);
            
            var topController = UIApplication.shared.keyWindow?.rootViewController;
            while (topController?.presentedViewController != nil) {
                topController = topController?.presentedViewController;
            }
            
            if topController != nil {
                let controller = (userInfo["type"] as? String == "muc") ? UIStoryboard(name: "Groupchat", bundle: nil).instantiateViewController(withIdentifier: "RoomViewNavigationController") : topController!.storyboard?.instantiateViewController(withIdentifier: "ChatViewNavigationController");
                let navigationController = controller as? UINavigationController;
                let destination = navigationController?.visibleViewController ?? controller;
                
                if let baseChatViewController = destination as? BaseChatViewController {
                    baseChatViewController.account = accountJid;
                    baseChatViewController.jid = senderJid;
                }
                destination?.hidesBottomBarWhenPushed = true;
                
                topController!.showDetailViewController(controller!, sender: self);
            } else {
                print("No top controller!");
            }
        }
        #if targetEnvironment(simulator)
        #else
        if content.categoryIdentifier == "CALL" {
            let senderName = userInfo["senderName"] as! String;
            let senderJid = JID(userInfo["sender"] as! String);
            let accountJid = BareJID(userInfo["account"] as! String);
            let sdp = userInfo["sdpOffer"] as! String;
            let sid = userInfo["sid"] as! String;
            
            var topController = UIApplication.shared.keyWindow?.rootViewController;
            while (topController?.presentedViewController != nil) {
                topController = topController?.presentedViewController;
            }
            
            if let session = JingleManager.instance.session(for: accountJid, with: senderJid, sid: sid) {
                // can still can be received!
                let alert = UIAlertController(title: "Incoming call", message: "Incoming call from \(senderName)", preferredStyle: .alert);
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .denied, .restricted:
                    break;
                default:
                    alert.addAction(UIAlertAction(title: "Video call", style: .default, handler: { action in
                        // accept video
                        VideoCallController.accept(session: session, sdpOffer: sdp, withAudio: true, withVideo: true, sender: topController!);
                    }))
                }
                alert.addAction(UIAlertAction(title: "Audio call", style: .default, handler: { action in
                    VideoCallController.accept(session: session, sdpOffer: sdp, withAudio: true, withVideo: false, sender: topController!);
                }));
                alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: { action in
                    _ = session.decline();
                }));
                topController?.present(alert, animated: true, completion: nil);
            } else {
                // call missed...
                let alert = UIAlertController(title: "Missed call", message: "Missed incoming call from \(senderName)", preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil));
                
                topController?.present(alert, animated: true, completion: nil);
            }
        }
        #endif
        completionHandler();
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if notification.request.content.categoryIdentifier == "MESSAGE" || notification.request.content.categoryIdentifier == "MESSAGE_NO_SENDER" {
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
    
    func isChatVisible(account acc: String?, with j: String?) -> Bool {
        guard let account = acc, let jid = j else {
            return false;
        }
        var topController = UIApplication.shared.keyWindow?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }
        guard let splitViewController = topController as? UISplitViewController else {
            return false;
        }
        
        guard let selectedTabController = splitViewController.viewControllers.map({(controller) in controller as? UITabBarController }).filter({ (controller) -> Bool in
            controller != nil
        }).map({(controller) in controller! }).first?.selectedViewController else {
            return false;
        }
        
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
        return (baseChatController!.account == BareJID(account)) && (baseChatController!.jid == BareJID(jid));
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
        if let account = JID(userInfo[AnyHashable("account")] as? String) {
            let sender = JID(userInfo[AnyHashable("sender")] as? String);
            let body = userInfo[AnyHashable("body")] as? String;
            if let unreadMessages = userInfo[AnyHashable("unread-messages")] as? Int, unreadMessages == 0 && sender == nil && body == nil {
                let state = self.xmppService.getClient(forJid: account.bareJid)?.state;
                print("unread messages retrieved, client state =", state as Any);
                if state != .connected {
                    dismissPushNotifications(for: account) {
                        completionHandler(.newData);
                    }
                    return;
                }
            } else if body != nil {
                if sender != nil {
                    let nickname = userInfo[AnyHashable("nickname")] as? String;
                    notifyNewMessage(account: account, sender: sender!, body: body!, type: nickname == nil ? "chat" : "muc", data: userInfo, isPush: true) {
                        completionHandler(.newData);
                    }
                    return;
                } else {
                    notifyNewMessageWaiting(account: account) {
                        completionHandler(.newData);
                    }
                    return;
                }
            }
        }
        
        completionHandler(.newData);
    }
    
    func notifyNewMessageWaiting(account: JID, completionHandler: @escaping ()->Void) {
        let threadId = "account=" + account.stringValue;
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let content = UNMutableNotificationContent();
            content.body = "New message received!";
            content.sound = UNNotificationSound.default;
            content.categoryIdentifier = "MESSAGE_NO_SENDER";
            content.userInfo = ["account": account.stringValue, "push": true];
            content.threadIdentifier = threadId;
                
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil), withCompletionHandler: {(error) in
                print("message notification error", error as Any);
                self.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
            });
        }
    }
    
    func notifyNewMessage(account: BareJID, sender: BareJID, body: String, type: String?, isPush: Bool, completionHandler: (()->Void)?) {
        notifyNewMessage(account: JID(account), sender: JID(sender), body: body, type: type, data: [:], isPush: isPush, completionHandler: completionHandler);
    }
    
    func notifyNewMessage(account: JID, sender: JID, body: String, type: String?, data userInfo: [AnyHashable:Any], isPush: Bool, completionHandler: (()->Void)?) {
        guard userInfo["carbonAction"] == nil else {
            return;
        }
        
        var alertBody: String?;
        switch (type ?? "chat") {
        case "muc":
            guard let mucModule: MucModule = xmppService.getClient(forJid: account.bareJid)?.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            guard let room: DBRoom = mucModule.roomsManager.getRoom(for: sender.bareJid) as? DBRoom else {
                return;
            }
            guard let nick = userInfo["senderName"] as? String ?? userInfo[AnyHashable("nickname")] as? String else {
                return;
            }

            switch room.options.notifications {
            case .none:
                return;
            case .always:
                alertBody = "\(nick): \(body)";
            case .mention:
                let myNickname = room.nickname;
                if body.contains(myNickname) {
                    alertBody = "\(nick) mentioned you: \(body)";
                } else {
                    return;
                }
            }
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
        
        let id = threadId + ":body=" + body.prefix(400);
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            if notifications.filter({(notification) in  notification.request.identifier == id}).isEmpty {
                let content = UNMutableNotificationContent();
                //content.title = "Received new message from \(senderName!)";
                content.body = alertBody!;
                content.sound = UNNotificationSound.default;
                content.userInfo = ["account": account.stringValue, "sender": sender.bareJid.stringValue, "push": isPush, "type": (type ?? "chat")];
                content.categoryIdentifier = "MESSAGE";
                content.threadIdentifier = threadId;
                
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil), withCompletionHandler: {(error) in
                    print("message notification error", error as Any);
                    self.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
                });
            }
        }
    }
    
    @objc func newMessage(_ notification: NSNotification) {
        guard let message = notification.object as? ChatMessage else {
            return;
        }
        guard message.state == .incoming_unread || message.state == .incoming_error_unread || message.encryption == .notForThisDevice else {
            return;
        }
        
        notifyNewMessage(account: message.account, sender: message.jid, body: message.message, type: message.authorNickname != nil ? "muc" : "chat", isPush: false, completionHandler: nil);
    }
    
    func dismissPushNotifications(for account: JID, completionHandler: (()-> Void)?) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let toRemove = notifications.filter({ (notification) in notification.request.content.categoryIdentifier == "MESSAGE" || notification.request.content.categoryIdentifier == "MESSAGE_NO_SENDER" }).filter({ (notification) in (notification.request.content.userInfo["account"] as? String) == account.stringValue && (notification.request.content.userInfo["push"] as? Bool ?? false) }).map({ (notification) in notification.request.identifier });
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
            self.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
        }
    }
    
    @objc func unreadMessagesCountChanged(_ notification: NSNotification) {
        updateApplicationIconBadgeNumber(completionHandler: nil);
    }
    
    @objc func presenceAuthorizationRequest(_ notification: NSNotification) {
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
    
    @objc func pushNotificationRegistrationFailed(_ notification: NSNotification) {
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
    
    @objc func mucRoomInvitationReceived(_ notification: Notification) {
        guard let e = notification.object as? MucModule.InvitationReceivedEvent, let account = e.sessionObject.userBareJid else {
            return;
        }
        
        let content = UNMutableNotificationContent();
        content.body = "Invitation to groupchat \(e.invitation.roomJid.stringValue)";
        if let from = e.invitation.inviter, let name = RosterModule.getRosterStore(e.sessionObject).get(for: from) {
            content.body = "\(content.body) from \(name)";
        }
        content.threadIdentifier = "mucRoomInvitation=" + account.stringValue + "|room=" + e.invitation.roomJid.stringValue;
        content.categoryIdentifier = "MUC_ROOM_INVITATION";
        content.userInfo = ["account": account.stringValue, "roomJid": e.invitation.roomJid.stringValue, "password": e.invitation.password as Any];
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil), withCompletionHandler: nil);
    }
    
    func updateApplicationIconBadgeNumber(completionHandler: (()->Void)?) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            var unreadChats = Set(notifications.filter({(notification) in notification.request.content.categoryIdentifier == "MESSAGE" }).map({ (notification) in
                return notification.request.content.threadIdentifier;
            }));
            
            DBChatStore.instance.getChats().filter({ chat -> Bool in
                return chat.unread > 0;
            }).forEach { (chat) in
                unreadChats.insert("account=" + chat.account.stringValue + "|sender=" + chat.jid.bareJid.stringValue)
            }
            let badge = unreadChats.count;
            DispatchQueue.main.async {
                print("setting badge to", badge);
                UIApplication.shared.applicationIconBadgeNumber = badge;
                completionHandler?();
            }
        }
    }
    
    @objc func serverCertificateError(_ notification: NSNotification) {
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
    
    @objc func authenticationFailure(_ notification: NSNotification) {
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
    
    func notifyUnsentMessages(count: Int) {
        let content = UNMutableNotificationContent();
        content.body = "It was not possible to send \(count) messages. Open the app to retry";
        content.categoryIdentifier = "UNSENT_MESSAGES";
        content.threadIdentifier = "unsent-messages";
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }

    func hideSetupGuide() {
        self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController();
        (self.window?.rootViewController as? UISplitViewController)?.preferredDisplayMode = .allVisible;
    }
 
    struct XmppUri {
        
        let jid: JID;
        let action: Action?;
        let dict: [String: String]?;
        
        init?(url: URL?) {
            guard url != nil else {
                return nil;
            }
            
            guard let components = URLComponents(url: url!, resolvingAgainstBaseURL: false) else {
                return nil;
            }
            
            guard components.host == nil else {
                return nil;
            }
            self.jid = JID(components.path);
            
            if var pairs = components.query?.split(separator: ";").map({ (it: Substring) -> [Substring] in it.split(separator: "=") }) {
                if let first = pairs.first, first.count == 1 {
                    action = Action(rawValue: String(first.first!));
                    pairs = Array(pairs.dropFirst());
                } else {
                    action = nil;
                }
                var dict: [String: String] = [:];
                for pair in pairs {
                    dict[String(pair[0])] = pair.count == 1 ? "" : String(pair[1]);
                }
                self.dict = dict;
            } else {
                self.action = nil;
                self.dict = nil;
            }
        }
        
        enum Action: String {
            case message
            case join
            case roster
        }
    }

}

