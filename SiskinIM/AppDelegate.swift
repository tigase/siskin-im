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
import Shared
import WebRTC
import BackgroundTasks

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    fileprivate let backgroundRefreshTaskIdentifier = "org.tigase.messenger.mobile.refresh";
    
    var window: UIWindow?
    var xmppService:XmppService! {
        return XmppService.instance;
    }
    var dbConnection:DBConnection! {
        return DBConnection.main;
    }
    
    let notificationCenterDelegate = NotificationCenterDelegate();
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if #available(iOS 13, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshTaskIdentifier, using: nil) { (task) in
                self.handleAppRefresh(task: task as! BGAppRefreshTask);
            }
        }
        try! DBConnection.migrateToGroupIfNeeded();
        RTCInitFieldTrialDictionary([:]);
        RTCInitializeSSL();
        RTCSetupInternalTracer();
        Log.initialize();
        Settings.initialize();
        AccountSettings.initialize();
        Appearance.sync();
        NotificationManager.instance.initialize(provider: MainNotificationManagerProvider());
        xmppService.initialize();
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            // sending notifications not granted!
        }
        UNUserNotificationCenter.current().delegate = self.notificationCenterDelegate;
        let categories = [
            UNNotificationCategory(identifier: "MESSAGE", actions: [], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "New message", options: [.customDismissAction])
        ];
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories));
        application.registerForRemoteNotifications();
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.unreadMessagesCountChanged), name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.serverCertificateError), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.authenticationFailure), name: XmppService.AUTHENTICATION_FAILURE, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.presenceAuthorizationRequest), name: XmppService.PRESENCE_AUTHORIZATION_REQUEST, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.mucRoomInvitationReceived), name: XmppService.MUC_ROOM_INVITATION, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.pushNotificationRegistrationFailed), name: Notification.Name("pushNotificationsRegistrationFailed"), object: nil);
        updateApplicationIconBadgeNumber(completionHandler: nil);
        
        if #available(iOS 13, *) {
        } else {
            application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum);
        }
        
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

    private var backgroundTaskId = UIBackgroundTaskIdentifier.invalid;
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        xmppService.applicationState = .inactive;

        backgroundTaskId = application.beginBackgroundTask {
            print("keep online on away background task expired", self.backgroundTaskId);
            self.applicationKeepOnlineOnAwayFinished(application);
        }
        print("keep online task started", backgroundTaskId, Date());
    }

    func applicationKeepOnlineOnAwayFinished(_ application: UIApplication) {
        let taskId = backgroundTaskId;
        guard taskId != .invalid else {
            return;
        }
        backgroundTaskId = .invalid;
        print("keep online task expired at", taskId, NSDate());
        self.xmppService.backgroundTaskFinished();
        print("keep online calling end background task", taskId, NSDate());
        if #available(iOS 13, *) {
            scheduleAppRefresh();
        }
        print("keep online task ended", taskId, NSDate());
        application.endBackgroundTask(taskId);
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        if #available(iOS 13.0, *) {
            Appearance.sync();
        }
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let toDiscard = notifications.filter({(notification) in
                switch NotificationCategory.from(identifier: notification.request.content.categoryIdentifier) {
                case .UNSENT_MESSAGES:
                    return true;
                case .MESSAGE:
                    return notification.request.content.userInfo["sender"] as? String == nil;
                default:
                    return false;
                }
                }).map({ (notiication) -> String in
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
        if #available(iOS 13, *) {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundRefreshTaskIdentifier);
        }
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        // TODO: XmppService::initialize() call in application:willFinishLaunchingWithOptions results in starting a connections while it may not always be desired if ie. app is relauched in the background due to crash
        // Shouldn't it wait for reconnection till it becomes active? or background refresh task is called?
        
        xmppService.applicationState = .active;
        applicationKeepOnlineOnAwayFinished(application);

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
    
    @available(iOS 13, *)
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskIdentifier);
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3500);
        
        do {
            try BGTaskScheduler.shared.submit(request);
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    @available(iOS 13, *)
    func handleAppRefresh(task: BGAppRefreshTask) {
        self.scheduleAppRefresh();
        let fetchStart = Date();
        print("starting fetching", fetchStart);
        xmppService.preformFetch(completionHandler: {(result) in
            let fetchEnd = Date();
            let time = fetchEnd.timeIntervalSince(fetchStart);
            print(Date(), "fetched date in \(time) seconds with result = \(result)");
            task.setTaskCompleted(success: result != .failed);
        });
        
        task.expirationHandler = {
            print("task expiration reached, start", Date());
            self.xmppService.performFetchExpired();
            print("task expiration reached, end", Date());
        }
    }
    
    static func isChatVisible(account acc: String?, with j: String?) -> Bool {
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
        if #available(iOS 13, *) {
            completionHandler(.noData);
        } else {
            let fetchStart = Date();
            print(Date(), "OLD: starting fetching data");
            xmppService.preformFetch(completionHandler: {(result) in
                completionHandler(result);
                let fetchEnd = Date();
                let time = fetchEnd.timeIntervalSince(fetchStart);
                print(Date(), "OLD: fetched date in \(time) seconds with result = \(result)");
            });
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)});
        
        print("Device Token:", tokenString)
        print("Device Token:", deviceToken.map({ String(format: "%02x", $0 )}).joined());
        PushEventHandler.instance.deviceId = tokenString;
//        Settings.DeviceToken.setValue(tokenString);
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register:", error);
        PushEventHandler.instance.deviceId = nil;
//        Settings.DeviceToken.setValue(nil);
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
                    dismissNewMessageNotifications(for: account) {
                        completionHandler(.newData);
                    }
                    return;
                }
            } else if body != nil {
                NotificationManager.instance.notifyNewMessage(account: account.bareJid, sender: sender?.bareJid, type: .unknown, nickname: userInfo[AnyHashable("nickname")] as? String, body: body!);
            }
        }
        
        completionHandler(.newData);
    }
        
    @objc func newMessage(_ notification: NSNotification) {
        guard let message = notification.object as? ChatMessage else {
            return;
        }
        guard message.state == .incoming_unread || message.state == .incoming_error_unread || message.encryption == .notForThisDevice else {
            return;
        }
        
        NotificationManager.instance.notifyNewMessage(account: message.account, sender: message.jid, type: message.authorNickname != nil ? .groupchat : .chat, nickname: message.authorNickname, body: message.message);
    }
    
    func dismissNewMessageNotifications(for account: JID, completionHandler: (()-> Void)?) {
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            let toRemove = notifications.filter({ (notification) in
                switch NotificationCategory.from(identifier: notification.request.content.categoryIdentifier) {
                case .MESSAGE:
                    return (notification.request.content.userInfo["account"] as? String) == account.stringValue;
                default:
                    return false;
                }
            }).map({ (notification) in notification.request.identifier });
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
        NotificationManager.instance.provider.countBadge(withThreadId: nil, completionHandler: { count in
            DispatchQueue.main.async {
                print("setting badge to", count);
                UIApplication.shared.applicationIconBadgeNumber = count;
                completionHandler?();
            }
        });
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
        content.sound = .default;
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

