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
    var defaultKeepOnlineOnAwayTime = NSTimeInterval(3 * 60);
    var keepOnlineOnAwayTimer: Timer?;
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        Log.initialize();
        Settings.initialize();
        do {
            dbConnection = try DBConnection(dbFilename: "mobile_messenger1.db");
            let resourcePath = NSBundle.mainBundle().resourcePath! + "/db-schema-1.0.0.sql";
            print("loading SQL from file", resourcePath);
            let dbSchema = try String(contentsOfFile: resourcePath, encoding: NSUTF8StringEncoding);
            print("loaded schema:", dbSchema);
            try dbConnection.execute(dbSchema);
        } catch _ {
            fatalError("Initialization of database failed!");
        }
        xmppService = XmppService(dbConnection: dbConnection);
        xmppService.updateXmppClientInstance();
        application.registerUserNotificationSettings(UIUserNotificationSettings(forTypes: [.Alert, .Badge, .Sound], categories: nil));
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AppDelegate.newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AppDelegate.chatItemsUpdated), name: DBChatHistoryStore.CHAT_ITEMS_UPDATED, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AppDelegate.serverCertificateError), name: "serverCertificateError", object: nil);
        updateApplicationIconBadgeNumber();
        
        // TODO: for now lets set 60, however we should use 600 in future
        application.setMinimumBackgroundFetchInterval(60);
        return true
    }

    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        xmppService.applicationState = .inactive;
        
        self.keepOnlineOnAwayTimer?.execute();
        self.keepOnlineOnAwayTimer = nil;
        
        var taskId = UIBackgroundTaskInvalid;
        taskId = application.beginBackgroundTaskWithExpirationHandler {
            print("keep online on away background task expired", taskId);
            self.applicationKeepOnlineOnAwayFinished(application, taskId: taskId);
        }
        
        let timeout = min(defaultKeepOnlineOnAwayTime, application.backgroundTimeRemaining - 8);
        print("keep online on away background task", taskId, "started at", NSDate(), "for", timeout, "s");
        
        self.keepOnlineOnAwayTimer = Timer(delayInSeconds: timeout, repeats: false, callback: {
            self.applicationKeepOnlineOnAwayFinished(application, taskId: taskId);
        });
    }

    func applicationKeepOnlineOnAwayFinished(application: UIApplication, taskId: UIBackgroundTaskIdentifier) {
        // make sure timer is cancelled
        self.keepOnlineOnAwayTimer?.cancel();
        self.keepOnlineOnAwayTimer = nil;
        print("keep online timer finished at", taskId, NSDate());
        // mark background task as ended
        application.endBackgroundTask(taskId);
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
        xmppService.applicationState = .active;
    }

    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        xmppService.applicationState = .active;
    }

    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        print(NSDate(), "application terminated!")
    }

    func application(application: UIApplication, didReceiveLocalNotification notification: UILocalNotification) {
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
                let alert = UIAlertController(title: "Certificate issue", message: "Server for domain \(accountJid.domain) provided invalid certificate for \(certName)\n with fingerprint\n\(certHash)\(issuer).\nDo you trust this certificate?", preferredStyle: .Alert);
                alert.addAction(UIAlertAction(title: "No", style: UIAlertActionStyle.Cancel, handler: nil));
                alert.addAction(UIAlertAction(title: "Yes", style: UIAlertActionStyle.Destructive, handler: {(action) in
                    print("accepted certificate!");
                    guard let account = AccountManager.getAccount(accountJid.stringValue) else {
                        return;
                    }
                    var certInfo = account.serverCertificate;
                    certInfo?["accepted"] = true;
                    account.serverCertificate = certInfo;
                    account.active = true;
                    AccountManager.updateAccount(account);
                }));
            
                var topController = UIApplication.sharedApplication().keyWindow?.rootViewController;
                while (topController?.presentedViewController != nil) {
                    topController = topController?.presentedViewController;
                }
                
                topController?.presentViewController(alert, animated: true, completion: nil);
            }
        }
    }
    
    func application(application: UIApplication, performFetchWithCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
        let fetchStart = NSDate();
        print(NSDate(), "starting fetching data");
        xmppService.preformFetch({(result) in
            completionHandler(result);
            let fetchEnd = NSDate();
            let time = fetchEnd.timeIntervalSinceDate(fetchStart);
            print(NSDate(), "fetched date in \(time) seconds with result = \(result)");
        });
    }
    
    func newMessage(notification: NSNotification) {
        let sender = notification.userInfo?["sender"] as? BareJID;
        let account = notification.userInfo?["account"] as? BareJID;
        let incoming:Bool = (notification.userInfo?["incoming"] as? Bool) ?? false;
        guard sender != nil && incoming else {
            return;
        }
        
        var senderName:String? = nil;
        if let sessionObject = xmppService.getClient(account!)?.sessionObject {
            senderName = RosterModule.getRosterStore(sessionObject).get(JID(sender!))?.name;
        }
        if senderName == nil {
            senderName = sender!.stringValue;
        }
        
        if UIApplication.sharedApplication().applicationState != .Active && notification.userInfo?["carbonAction"] == nil {
            var alertBody: String?;
            switch ((notification.userInfo?["type"] as? String) ?? "chat") {
            case "muc":
                if let body = (notification.userInfo?["body"] as? String) {
                    if body.containsString(notification.userInfo!["roomNickname"] as! String) {
                        alertBody = senderName! + " mentioned you";
                    }
                }
            default:
                alertBody = "Received new message from " + senderName!;
            }
            
            if alertBody != nil {
                var userNotification = UILocalNotification();
                userNotification.alertAction = "open";
                userNotification.alertBody = alertBody;
                userNotification.soundName = UILocalNotificationDefaultSoundName;
                //userNotification.applicationIconBadgeNumber = UIApplication.sharedApplication().applicationIconBadgeNumber + 1;
                userNotification.userInfo = ["account": account!.stringValue, "sender": account!.stringValue];
                userNotification.category = "MESSAGE";
                UIApplication.sharedApplication().presentLocalNotificationNow(userNotification);
            }
        }
        updateApplicationIconBadgeNumber();
    }
    
    func chatItemsUpdated(notification: NSNotification) {
        updateApplicationIconBadgeNumber();
    }
    
    func updateApplicationIconBadgeNumber() {
        let unreadChats = xmppService.dbChatHistoryStore.countUnreadChats();
        UIApplication.sharedApplication().applicationIconBadgeNumber = unreadChats;
    }
    
    func serverCertificateError(notification: NSNotification) {
        guard let certInfo = notification.userInfo else {
            return;
        }
        
        let account = BareJID(certInfo["account"] as! String);
        
        var userNotification = UILocalNotification();
        userNotification.alertAction = "fix";
        userNotification.alertBody = "Connection to server \(account.domain) failed";
        userNotification.userInfo = certInfo;
        userNotification.category = "ERROR";
        UIApplication.sharedApplication().presentLocalNotificationNow(userNotification);
    }

}

