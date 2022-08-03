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
import Martin
import Shared
import WebRTC
import BackgroundTasks
import Combine
import TigaseLogging
import Intents

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    fileprivate let backgroundRefreshTaskIdentifier = "org.tigase.messenger.mobile.refresh";
    
    var window: UIWindow?
    
    let notificationCenterDelegate = NotificationCenterDelegate();
    
    private var cancellables: Set<AnyCancellable> = [];
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "main");
    
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundRefreshTaskIdentifier, using: nil) { (task) in
            self.handleAppRefresh(task: task as! BGAppRefreshTask);
        }
//        RTCInitFieldTrialDictionary([:]);
        RTCInitializeSSL();
        //RTCSetupInternalTracer();
        AccountSettings.initialize();
        
        switch Settings.appearance {
        case .light:
            for window in application.windows {
                window.overrideUserInterfaceStyle = .light;
            }
        case .dark:
            for window in application.windows {
                window.overrideUserInterfaceStyle = .dark;
            }
        default:
            break;
        }
        Settings.$appearance.map({ $0.value }).receive(on: DispatchQueue.main).sink(receiveValue: { value in
            for window in application.windows {
                window.overrideUserInterfaceStyle = value;
            }
        }).store(in: &cancellables);
        _ = JingleManager.instance;
        UINavigationBar.appearance().tintColor = UIColor(named: "tintColor");
        _ = NotificationManager.instance;
        XmppService.instance.initialize();
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (granted, error) in
            if let error = error {
                self.logger.debug("error while requesting notifications authorization: \(error)");
            } else {
                DispatchQueue.main.async {
                    application.registerForRemoteNotifications();
                }
            }
        }
        UNUserNotificationCenter.current().delegate = self.notificationCenterDelegate;
        let categories = [
            UNNotificationCategory(identifier: "MESSAGE", actions: [], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: NSLocalizedString("New message", comment: "notification of incoming message on locked screen"), options: [.customDismissAction])
        ];
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories));
        
        
        CallManager.initializeCallManager();
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.serverCertificateError), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(AppDelegate.pushNotificationRegistrationFailed), name: Notification.Name("pushNotificationsRegistrationFailed"), object: nil);
        AccountManager.accountEventsPublisher.sink(receiveValue: { [weak self] action in
            guard case .removed(_) = action else {
                return;
            }
            if AccountManager.getAccounts().isEmpty {
                self?.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SetupViewController");
            }
        }).store(in: &cancellables);

        (self.window?.rootViewController as? UISplitViewController)?.preferredDisplayMode = .allVisible;
        if AccountManager.getAccounts().isEmpty {
            self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SetupViewController");
        }
                
        return true
    }
    
    func showSetup(value: Bool) {
        DispatchQueue.main.async {
            if let rootView = self.window?.rootViewController {
                let normalMode: Bool = rootView is UISplitViewController;
                let expNormalMode = !value;
                if normalMode != expNormalMode {
                    if expNormalMode {
                        (UIApplication.shared.delegate as? AppDelegate)?.hideSetupGuide();
                    } else {
                        self.window?.rootViewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SetupViewController");
                    }
                }
            }
        }
    }
    

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    private var backgroundTaskId = UIBackgroundTaskIdentifier.invalid;
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        XmppService.instance.updateApplicationState(.inactive);

        initiateBackgroundTask();
    }
    
    func initiateBackgroundTask() {
        guard XmppService.instance.applicationState != .active else {
            return;
        }
        let application = UIApplication.shared;
        backgroundTaskId = application.beginBackgroundTask {
            self.logger.debug("keep online on away background task \(self.backgroundTaskId) expired");
            self.applicationKeepOnlineOnAwayFinished(application);
        }
        if backgroundTaskId == .invalid {
            logger.debug("failed to start keep online background task");
            XmppService.instance.updateApplicationState(.suspended);
        } else {
            let taskId = backgroundTaskId;
            logger.debug("keep online task \(taskId) started");
        }
    }

    func applicationKeepOnlineOnAwayFinished(_ application: UIApplication) {
        let taskId = backgroundTaskId;
        guard taskId != .invalid else {
            return;
        }
        backgroundTaskId = .invalid;
        logger.debug("keep online task \(taskId) expired");
        XmppService.instance.updateApplicationState(.suspended);
        XmppService.instance.backgroundTaskFinished();
        logger.debug("keep online calling end background task \(taskId)");
        scheduleAppRefresh();
        logger.debug("keep online task \(taskId) ended");
        application.endBackgroundTask(taskId);
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        CallManager.initializeCallManager();
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
            NotificationManager.instance.updateApplicationIconBadgeNumber(completionHandler: nil);
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: backgroundRefreshTaskIdentifier);
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        
        // TODO: XmppService::initialize() call in application:willFinishLaunchingWithOptions results in starting a connections while it may not always be desired if ie. app is relauched in the background due to crash
        // Shouldn't it wait for reconnection till it becomes active? or background refresh task is called?
        
        XmppService.instance.updateApplicationState(.active);
        applicationKeepOnlineOnAwayFinished(application);

        NotificationManager.instance.updateApplicationIconBadgeNumber(completionHandler: nil);
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        RTCShutdownInternalTracer();
        RTCCleanupSSL();
        logger.debug("application terminated!")
    }
    
    func application(_ application: UIApplication, continue activity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
         
        guard let intent = activity.interaction?.intent as? INSendMessageIntent else {
            return false;
        }
        
        guard let account = BareJID(intent.sender?.personHandle?.value), AccountManager.getAccount(for: account)?.active ?? false else {
            return false;
        }
        
        guard let recipient = BareJID(intent.recipients?.first?.personHandle?.value) else {
            return false;
        }
        
        guard let xmppClient = XmppService.instance.getClient(for: account) else {
            return false;
        }
        
        var chatToOpen: Chat?;
        switch DBChatStore.instance.createChat(for: xmppClient, with: recipient) {
        case .created(let chat):
            chatToOpen = chat;
        case .found(let chat):
            chatToOpen = chat;
        case .none:
            return false;
        }
        
        guard let destination = self.window?.rootViewController?.storyboard?.instantiateViewController(withIdentifier: "ChatViewNavigationController") as? UINavigationController else {
            return false;
        }
        
        let chatController = destination.children[0] as! ChatViewController;
        chatController.hidesBottomBarWhenPushed = true;
        chatController.conversation = chatToOpen;
        self.window?.rootViewController?.showDetailViewController(destination, sender: self);
        
        return true;
    }
    
//    func application(_ application: UIApplication, handlerFor intent: INIntent) -> Any? {
//        guard let sendMessageIntent = intent as? INSendMessageIntent, sendMessageIntent.content == nil else {
//            return nil;
//        }
//
//        return SendMessageIntentHandler();
//    }
//
//    class SendMessageIntentHandler: NSObject, INSendMessageIntentHandling {
//
//        func handle(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
//            guard let account = BareJID(intent.sender?.personHandle?.value) else {
//                completion(.init(code: .failure, userActivity: nil));
//                return;
//            }
//            guard let recipient = BareJID(intent.recipients?.first?.personHandle?.value) else {
//                completion(.init(code: .failure, userActivity: nil));
//                return;
//            }
//        }
//
//    }
    
    
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false;
        }
        
        logger.debug("got url to open: \(components)");
        guard let xmppUri = XmppUri(url: url) else {
            return false;
        }
        logger.debug("got xmpp url with jid: \(xmppUri.jid), action: \(xmppUri.action as Any), params: \(xmppUri.dict as Any)");

        if let action = xmppUri.action {
            self.open(xmppUri: xmppUri, action: action);
            return true;
        } else {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: NSLocalizedString("Open URL", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("What do you want to do with %@?", comment: "alert body"), url.description), preferredStyle: .alert);
                alert.addAction(UIAlertAction(title: NSLocalizedString("Open chat", comment: "action label"), style: .default, handler: { (action) in
                    self.open(xmppUri: xmppUri, action: .message);
                }))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Join room", comment: "action label"), style: .default, handler: { (action) in
                    self.open(xmppUri: xmppUri, action: .join);
                }))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Add contact", comment: "action label"), style: .default, handler: { (action) in
                    self.open(xmppUri: xmppUri, action: .roster);
                }))
                alert.addAction(UIAlertAction(title: NSLocalizedString("Nothing", comment: "action label"), style: .cancel, handler: nil));
                self.window?.rootViewController?.present(alert, animated: true, completion: nil);
            }
            return false;
        }
    }
    
    func open(xmppUri: XmppUri, action: XmppUri.Action, then: (()->Void)? = nil) {
        switch action {
        case .join:
            let navController = UIStoryboard(name: "MIX", bundle: nil).instantiateViewController(withIdentifier: "ChannelJoinNavigationViewController") as! UINavigationController;
            let joinController = navController.visibleViewController as! ChannelSelectToJoinViewController;
            joinController.joinConversation = (xmppUri.jid.bareJid, xmppUri.dict?["password"]);

            
            joinController.hidesBottomBarWhenPushed = true;
            navController.modalPresentationStyle = .formSheet;
            window?.rootViewController?.dismiss(animated: true, completion: {
                self.window?.rootViewController?.present(navController, animated: true, completion: nil);
            })
        case .message:
            let alert = UIAlertController(title: NSLocalizedString("Start chatting", comment: "alert title"), message: NSLocalizedString("Select account to open chat from", comment: "alert body"), preferredStyle: .alert);
            
            let accounts = XmppService.instance.clients.values.map({ (client) -> BareJID in
                return client.userBareJid;
            }).sorted { (a1, a2) -> Bool in
                return a1.stringValue.compare(a2.stringValue) == .orderedAscending;
            }
            
            let openChatFn: (BareJID)->Void = { (account) in
                guard let xmppClient = XmppService.instance.getClient(for: account) else {
                    return;
                }
                
                var chatToOpen: Chat?;
                switch DBChatStore.instance.createChat(for: xmppClient, with: xmppUri.jid.bareJid) {
                case .created(let chat):
                    chatToOpen = chat;
                case .found(let chat):
                    chatToOpen = chat;
                case .none:
                    return;
                }
                
                guard let destination = self.window?.rootViewController?.storyboard?.instantiateViewController(withIdentifier: "ChatViewNavigationController") as? UINavigationController else {
                    return;
                }
                
                let chatController = destination.children[0] as! ChatViewController;
                chatController.hidesBottomBarWhenPushed = true;
                chatController.conversation = chatToOpen;
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
            if let dict = xmppUri.dict, let ibr = dict["ibr"], ibr == "y" {
                guard !AccountManager.getAccounts().isEmpty else {
                    self.open(xmppUri: XmppUri(jid: JID(xmppUri.jid.domain), action: .register, dict: dict), action: .register, then: {
                        DispatchQueue.main.async {
                            self.open(xmppUri: xmppUri, action: action);
                        }
                    });
                    return;
                }
            }
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
                itemEditController?.preauth = xmppUri.dict?["preauth"];
            });
        case .register:
            let alert = UIAlertController(title: NSLocalizedString("Registering account", comment: "alert title"), message: xmppUri.jid.localPart == nil ? String.localizedStringWithFormat(NSLocalizedString("Do you wish to register a new account at %@?", comment: "alert body"), xmppUri.jid.domain!) : String.localizedStringWithFormat(NSLocalizedString("Do you wish to register a new account %@?", comment: "alert body"), xmppUri.jid.stringValue), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .default, handler: { action in
                let registerAccountController = RegisterAccountController.instantiate(fromAppStoryboard: .Account);
                registerAccountController.hidesBottomBarWhenPushed = true;
                registerAccountController.account = xmppUri.jid.bareJid;
                registerAccountController.preauth = xmppUri.dict?["preauth"];
                registerAccountController.onAccountAdded = then;
                self.window?.rootViewController?.showDetailViewController(UINavigationController(rootViewController: registerAccountController), sender: self);
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .cancel, handler: nil));
            self.window?.rootViewController?.present(alert, animated: true, completion: nil);
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskIdentifier);
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3500);
        
        do {
            try BGTaskScheduler.shared.submit(request);
        } catch {
            logger.error("Could not schedule app refresh: \(error)")
        }
    }
    
    var backgroundFetchInProgress = false;
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        guard DispatchQueue.main.sync(execute: {
            if self.backgroundFetchInProgress {
                return false;
            }
            backgroundFetchInProgress = true;
            return true;
        }) else {
            task.setTaskCompleted(success: true);
            return;
        }
        self.scheduleAppRefresh();
        let fetchStart = Date();
        logger.debug("starting fetching");
        XmppService.instance.preformFetch(completionHandler: {(result) in
            let fetchEnd = Date();
            let time = fetchEnd.timeIntervalSince(fetchStart);
            self.logger.debug("fetched data in \(time) seconds with result = \(result)");
            self.backgroundFetchInProgress = false;
            task.setTaskCompleted(success: result != .failed);
        });
        
        task.expirationHandler = {
            self.logger.debug("task expiration reached, start");
            DispatchQueue.main.sync {
                self.backgroundFetchInProgress = false;
            }
            XmppService.instance.performFetchExpired();
            self.logger.debug("task expiration reached, end");
        }
    }
    
    static func isChatVisible(account acc: String?, with j: String?) -> Bool {
        guard let account = acc, let jid = j else {
            return false;
        }
        
        guard let baseChatController = AppDelegate.getChatController(visible: true) else {
            return false;
        }
        
        return (baseChatController.conversation.account == BareJID(account)) && (baseChatController.conversation.jid == BareJID(jid));
    }
    
    static func getChatController(visible: Bool) -> BaseChatViewController? {
        var topController = UIApplication.shared.windows.first(where:{ $0.isKeyWindow })?.rootViewController;
        while (topController?.presentedViewController != nil) {
            topController = topController?.presentedViewController;
        }
        guard let splitViewController = topController as? UISplitViewController else {
            return nil;
        }
        
        guard let navigationController = navigationController(fromSplitViewController: splitViewController) else {
            return nil;
        }
        
            if visible {
                return navigationController.viewControllers.last as? BaseChatViewController;
            } else {
                for controller in navigationController.viewControllers.reversed() {
                    if let baseChatViewController = controller as? BaseChatViewController {
                        return baseChatViewController;
                    }
                }
                return nil;
            }
//        } else {
//            return selectedTabController as? BaseChatViewController;
//        }
    }
    
    private static func navigationController(fromSplitViewController splitViewController: UISplitViewController) -> UINavigationController? {
        if splitViewController.isCollapsed {
            return splitViewController.viewControllers.first(where: { $0 is UITabBarController }).map({ $0 as! UITabBarController })?.selectedViewController as? UINavigationController;
        } else {
            return splitViewController.viewControllers.first(where: { !($0 is UITabBarController) }) as? UINavigationController;
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)});
        
        logger.debug("registered for remote notifications, got device token: \(deviceToken.map({ String(format: "%02x", $0 )}).joined(), privacy: .public)");
        PushEventHandler.instance.deviceId = tokenString;
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("failed to register for remote notifications: \(error, privacy: .public)");
        PushEventHandler.instance.deviceId = nil;
        Settings.enablePush = false;
//        Settings.DeviceToken.setValue(nil);
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any]) {
        logger.debug("Push notification received: \(userInfo)");
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        logger.debug("Push notification received with fetch request: \(userInfo)");
        //let fetchStart = Date();
        if let account = JID(userInfo[AnyHashable("account")] as? String) {
            let sender = JID(userInfo[AnyHashable("sender")] as? String);
            let body = userInfo[AnyHashable("body")] as? String;
            
            if let unreadMessages = userInfo[AnyHashable("unread-messages")] as? Int, unreadMessages == 0 && sender == nil && body == nil {
                let state = XmppService.instance.getClient(for: account.bareJid)?.state;
                logger.debug("unread messages retrieved, client state = \(state, privacy: .public)");
                if state != .connected() {
                    dismissNewMessageNotifications(for: account) {
                        completionHandler(.newData);
                    }
                    return;
                }
            } else if body != nil {
                // FIXME: not sure about this `date`!!
                NotificationManager.instance.notifyNewMessage(account: account.bareJid, sender: sender?.bareJid, nickname: userInfo[AnyHashable("nickname")] as? String, body: body!, date: Date());
            } else {
                if let encryped = userInfo["encrypted"] as? String, let ivStr = userInfo["iv"] as? String, let key = NotificationEncryptionKeys.key(for: account.bareJid), let data = Data(base64Encoded: encryped), let iv = Data(base64Encoded: ivStr) {
                    logger.debug("got encrypted push with known key");
                    let cipher = Cipher.AES_GCM();
                    var decoded = Data();
                    if cipher.decrypt(iv: iv, key: key, encoded: data, auth: nil, output: &decoded) {
                        logger.debug("got decrypted data: \(String(data: decoded, encoding: .utf8) as Any)");
                        if let payload = try? JSONDecoder().decode(Payload.self, from: decoded) {
                            logger.debug("decoded payload successfully!");
                            // we require `media` to be present (even empty) in incoming push for jingle session initiation,
                            // so we can assume that if `media` is `nil` then this is a push for call termination
                            if let sid = payload.sid, payload.media == nil {
                                guard CallManager.isAvailable else {
                                    completionHandler(.newData);
                                    return;
                                }
                                CallManager.instance?.endCall(on: account.bareJid, with: payload.sender.bareJid, sid: sid, completionHandler: {
                                    self.logger.debug("ended call");
                                    completionHandler(.newData);
                                })
                                return;
                            }
                        }
                        
                    }
                }
            }
        }
        
        completionHandler(.newData);
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
            NotificationManager.instance.updateApplicationIconBadgeNumber(completionHandler: completionHandler);
        }
    }
    
    @objc func pushNotificationRegistrationFailed(_ notification: NSNotification) {
        let account = notification.userInfo?["account"] as? BareJID;
        let errorCondition = (notification.userInfo?["errorCondition"] as? ErrorCondition) ?? ErrorCondition.internal_server_error;
        let content = UNMutableNotificationContent();
        switch errorCondition {
        case .remote_server_timeout:
            content.body = NSLocalizedString("It was not possible to contact push notification component.\nTry again later.", comment: "push notifications registration failure message")
        case .remote_server_not_found:
            content.body = NSLocalizedString("It was not possible to contact push notification component.", comment: "push notifications registration failure message")
        case .service_unavailable:
            content.body = NSLocalizedString("Push notifications not available", comment: "push notifications registration failure message")
        default:
            content.body = String.localizedStringWithFormat(NSLocalizedString("It was not possible to contact push notification component: %@", comment: "push notifications registration failure message"), errorCondition.rawValue);
        }
        content.threadIdentifier = "account=" + account!.stringValue;
        content.categoryIdentifier = "ERROR";
        content.userInfo = ["account": account!.stringValue];
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }
    
    @objc func serverCertificateError(_ notification: NSNotification) {
        guard let certInfo = notification.userInfo else {
            return;
        }
        
        let account = BareJID(certInfo["account"] as! String);
        
        let content = UNMutableNotificationContent();
        content.body = String.localizedStringWithFormat(NSLocalizedString("Connection to server %@ failed", comment: "error notification message"), account.domain);
        content.userInfo = certInfo;
        content.categoryIdentifier = "ERROR";
        content.threadIdentifier = "account=" + account.stringValue;
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }
    
    func notifyUnsentMessages(count: Int) {
        let content = UNMutableNotificationContent();
        content.body = String.localizedStringWithFormat(NSLocalizedString("It was not possible to send %d messages. Open the app to retry", comment: "unsent messages notification"), count);
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
        
        init(jid: JID, action: Action?, dict: [String:String]?) {
            self.jid = jid;
            self.action = action;
            self.dict = dict;
        }
        
        func toURL() -> URL? {
            var parts = URLComponents();
            parts.scheme = "xmpp";
            parts.path = jid.stringValue;
            if action != nil {
                parts.query = action!.rawValue + (dict?.map({ (k,v) -> String in ";\(k)=\(v)"}).joined() ?? "");
            } else {
                parts.query = dict?.map({ (k,v) -> String in ";\(k)=\(v)"}).joined();
            }
            return parts.url;
        }
        
        enum Action: String {
            case message
            case join
            case roster
            case register
        }
    }

}

