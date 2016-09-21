//
// XmppService.swift
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

open class XmppService: Logger, EventHandler {
    
    open static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    open static let AUTHENTICATION_FAILURE = Notification.Name("authenticationFailure");
    
    open var fetchTimeShort: TimeInterval = 5;
    open var fetchTimeLong: TimeInterval = 20;
    
    fileprivate var creationDate = NSDate();
    
    fileprivate let dbConnection: DBConnection;
    open var avatarManager: AvatarManager!;
    open let dbCapsCache: DBCapabilitiesCache;
    open let dbChatStore: DBChatStore;
    open let dbChatHistoryStore: DBChatHistoryStore;
    fileprivate let dbRosterStore: DBRosterStore;
    open let dbVCardsCache: DBVCardsCache;
    
    open var applicationState: ApplicationState {
        didSet {
            if oldValue != applicationState {
                applicationStateChanged();
            }
            if applicationState != .active {
                avatarManager.clearCache();
            }
        }
    }
    
    fileprivate let reachability: Reachability;
    
    fileprivate var clients = [BareJID:XMPPClient]();
    
    fileprivate var eventHandlers: [EventHandlerHolder] = [];
    
    fileprivate var networkAvailable:Bool {
        didSet {
            if networkAvailable {
                if !oldValue {
                    connectClients();
                } else {
                    keepalive();
                }
            } else if !networkAvailable && oldValue {
                disconnectClients(true);
            }
        }
    }
    
    fileprivate var backgroundFetchCompletionHandler: ((UIBackgroundFetchResult)->Void)?;
    fileprivate var backgroundFetchTimer: TigaseSwift.Timer?;
    
    fileprivate var sslCertificateValidator: ((SessionObject,SecTrust) -> Bool)?;
    
    init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        self.dbCapsCache = DBCapabilitiesCache(dbConnection: dbConnection);
        self.dbChatStore = DBChatStore(dbConnection: dbConnection);
        self.dbChatHistoryStore = DBChatHistoryStore(dbConnection: dbConnection);
        self.dbRosterStore = DBRosterStore(dbConnection: dbConnection);
        self.dbVCardsCache = DBVCardsCache(dbConnection: dbConnection);
        self.reachability = Reachability();
        self.networkAvailable = false;
        self.applicationState = UIApplication.shared.applicationState == .active ? .active : .inactive;

        super.init();

        self.sslCertificateValidator = {(sessionObject: SessionObject, trust: SecTrust) -> Bool in
            return self.validateSslCertificate(sessionObject, trust: trust);
        };

        self.avatarManager = AvatarManager(xmppService: self);
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.accountConfigurationChanged), name: AccountManager.ACCOUNT_CONFIGURATION_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.connectivityChanged), name: Reachability.CONNECTIVITY_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.settingsChanged), name: Settings.SETTINGS_CHANGED, object: nil);
        networkAvailable = reachability.isConnectedToNetwork();
    
    }
    
    open func updateXmppClientInstance() {
        for account in AccountManager.getAccounts() {
            updateXmppClientInstance(BareJID(account));
        }
    }
    
    open func updateXmppClientInstance(_ userJid:BareJID) {
        print("updating xmppclient instance for", userJid);
        var client = clients[userJid];
        let password = AccountManager.getAccountPassword(userJid.stringValue);
        let config = AccountManager.getAccount(userJid.stringValue);
        
        if client == nil {
            if password == nil || config == nil || config?.active != true {
                return;
            }
            client = XMPPClient()
            client!.keepaliveTimeout = 0;
            registerModules(client!);
            registerEventHandlers(client!);
            
            client?.sessionObject.setUserProperty(SocketConnector.SSL_CERTIFICATE_VALIDATOR, value: self.sslCertificateValidator);
        } else {
            if client?.state != SocketConnector.State.disconnected {
                client?.disconnect();
                return;
            }
            
            if password == nil || config == nil || config?.active != true {
                clients.removeValue(forKey: userJid);
                unregisterEventHandlers(client!);
                return;
            }
        }
        
        client?.connectionConfiguration.setUserJID(userJid);
        client?.connectionConfiguration.setUserPassword(password);
        
        // Setting resource to use - using device name
        client?.sessionObject.setUserProperty(SessionObject.RESOURCE, value: UIDevice.current.name);
        
        // Setting software name, version and OS name
        client?.sessionObject.setUserProperty(SoftwareVersionModule.NAME_KEY, value: Bundle.main.infoDictionary!["CFBundleName"] as! String);
        client?.sessionObject.setUserProperty(SoftwareVersionModule.VERSION_KEY, value: Bundle.main.infoDictionary!["CFBundleVersion"] as! String);
        client?.sessionObject.setUserProperty(SoftwareVersionModule.OS_KEY, value: UIDevice.current.systemName);
        
        
        clients[userJid] = client;
        
        if networkAvailable {
            client?.login();
        } else {
            client?.modulesManager.initIfRequired();
        }
    }
    
    open func getClient(_ account:BareJID) -> XMPPClient? {
        return clients[account];
    }
    
    fileprivate func registerModules(_ client:XMPPClient) {
        let smModule = client.modulesManager.register(StreamManagementModule());
        smModule.maxResumptionTimeout = 3600;
        client.modulesManager.register(AuthModule());
        client.modulesManager.register(StreamFeaturesModule());
        client.modulesManager.register(SaslModule());
        client.modulesManager.register(ResourceBinderModule());
        client.modulesManager.register(SessionEstablishmentModule());
        client.modulesManager.register(DiscoveryModule());
        client.modulesManager.register(SoftwareVersionModule());
        client.modulesManager.register(VCardModule());
        client.modulesManager.register(ClientStateIndicationModule());
        client.modulesManager.register(MobileModeModule());
        client.modulesManager.register(PingModule());
        let rosterModule =  client.modulesManager.register(RosterModule());
        rosterModule.rosterStore = DBRosterStoreWrapper(sessionObject: client.sessionObject, store: dbRosterStore);
        rosterModule.versionProvider = dbRosterStore;
        client.modulesManager.register(PresenceModule());
        let messageModule = client.modulesManager.register(MessageModule());
        let chatManager = DefaultChatManager(context: client.context, chatStore: DBChatStoreWrapper(sessionObject: client.sessionObject, store: dbChatStore));
        messageModule.chatManager = chatManager;
        client.modulesManager.register(MessageCarbonsModule());
        let mucModule = MucModule();
        mucModule.roomsManager = DBRoomsManager(store: dbChatStore);
        client.modulesManager.register(mucModule);
        let capsModule = client.modulesManager.register(CapabilitiesModule());
        capsModule.cache = dbCapsCache;
    }
    
    fileprivate func registerEventHandlers(_ client:XMPPClient) {
        client.eventBus.register(self, events: SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, PresenceModule.BeforePresenceSendEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE, AuthModule.AuthFailedEvent.TYPE);
        client.eventBus.register(dbChatHistoryStore, events: MessageModule.MessageReceivedEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE);
        for holder in eventHandlers {
            client.eventBus.register(holder.handler, events: holder.events);
        }
    }
    
    fileprivate func unregisterEventHandlers(_ client:XMPPClient) {
        client.eventBus.unregister(self, events: SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, PresenceModule.BeforePresenceSendEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE, AuthModule.AuthFailedEvent.TYPE);
        client.eventBus.unregister(dbChatHistoryStore, events: MessageModule.MessageReceivedEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE);
        for holder in eventHandlers {
            client.eventBus.unregister(holder.handler, events: holder.events);
        }
    }
    
    open func handleEvent(_ event: Event) {
        switch event {
        case let e as SocketConnector.CertificateErrorEvent:
            // at first let's disable account so it will not try to reconnect
            // until user will take action
            let certCount = SecTrustGetCertificateCount(e.trust);
            print("cert count", certCount);
            
            var certInfo: [String: AnyObject] = [:];
            
            for i in 0..<certCount {
                let cert = SecTrustGetCertificateAtIndex(e.trust, i);
                let fingerprint = Digest.sha1.digestToHex(SecCertificateCopyData(cert!) as Data);
                // on first cert got 03469208e5d8e580f65799497d73b2d3098e8c8a
                // while openssl reports: SHA1 Fingerprint=03:46:92:08:E5:D8:E5:80:F6:57:99:49:7D:73:B2:D3:09:8E:8C:8A
                let summary = SecCertificateCopySubjectSummary(cert!)
                print("cert", cert!, "SUMMARY:", summary, "fingerprint:", fingerprint);
                switch i {
                case 0:
                    certInfo["cert-name"] = summary;
                    certInfo["cert-hash-sha1"] = fingerprint as NSString?;
                case 1:
                    certInfo["issuer-name"] = summary;
                    certInfo["issuer-hash-sha1"] = fingerprint as NSString?;
                default:
                    break;
                }
            }
            print("cert info =", certInfo);
            
            if let account = AccountManager.getAccount(e.sessionObject.userBareJid!.stringValue) {
                account.active = false;
                account.serverCertificate = certInfo;
                AccountManager.updateAccount(account, notifyChange: false);
            }
            
            var info = certInfo;
            info["account"] = e.sessionObject.userBareJid!.stringValue as NSString;
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: self, userInfo: info);
            }
        case let e as SocketConnector.DisconnectedEvent:
            increaseBackgroundFetchTimeIfNeeded();
            networkAvailable = reachability.isConnectedToNetwork();
            if let jid = e.sessionObject.userBareJid {
                DispatchQueue.global(qos: .default).async {
                    self.updateXmppClientInstance(jid);
                }
            }
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            if e.features.contains(MessageCarbonsModule.MC_XMLNS) {
                if let messageCarbonsModule: MessageCarbonsModule = getClient(e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) {
                    if Settings.EnableMessageCarbons.getBool() {
                        messageCarbonsModule.enable();
                    }
                }
            }
        case let e as PresenceModule.BeforePresenceSendEvent:
            if UIApplication.shared.applicationState == .active {
                e.presence.show = Presence.Show.online;
                e.presence.priority = 5;
            } else {
                e.presence.show = Presence.Show.away;
                e.presence.priority = 0;
            }
            e.presence.status = Settings.StatusMessage.getString();
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            if applicationState == .inactive {
                let client = getClient(e.sessionObject.userBareJid!);
                let csiModule: ClientStateIndicationModule? = client?.modulesManager.getModule(ClientStateIndicationModule.ID);
                if csiModule != nil && csiModule!.available {
                    csiModule!.setState(applicationState == .active);
                }
                else if let mobileModeModule: MobileModeModule = client?.modulesManager.getModule(MobileModeModule.ID) {
                    mobileModeModule.enable();
                }
            }
            reconnectMucRooms(e.sessionObject.userBareJid!);
        case let e as AuthModule.AuthFailedEvent:
            if let account = AccountManager.getAccount(e.sessionObject.userBareJid!.stringValue) {
                account.active = false;
                AccountManager.updateAccount(account, notifyChange: true);
            }
            var info: [String: AnyObject] = [:];
            info["account"] = e.sessionObject.userBareJid!.stringValue as NSString;
            info["auth-error-type"] = e.error.rawValue as NSString;
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: XmppService.AUTHENTICATION_FAILURE, object: self, userInfo: info);
            }
        default:
            log("received unsupported event", event);
        }
    }
    
    open func keepalive() {
        for client in clients.values {
            client.keepalive();
        }
    }
    
    fileprivate func applicationStateChanged() {
        sendAutoPresence();
        for client in clients.values {
            if client.state == .connected {
                let csiModule: ClientStateIndicationModule? = client.modulesManager.getModule(ClientStateIndicationModule.ID);
                if csiModule != nil && csiModule!.available {
                    csiModule!.setState(applicationState == .active);
                }
                else if let mobileModeModule: MobileModeModule = client.modulesManager.getModule(MobileModeModule.ID) {
                    mobileModeModule.setState(applicationState == .inactive);
                }
            }
        }
    }
    
    fileprivate func sendAutoPresence() {
        for client in clients.values {
            if client.state == .connected {
                if let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) {
                    presenceModule.setPresence(.online, status: nil, priority: nil);
                }
            }
        }
    }
    
    open func registerEventHandler(_ handler:EventHandler, events:Event...) {
        log("registered event handler", handler, "for", events);
        eventHandlers.append(EventHandlerHolder(handler: handler, events: events));
        for client in clients.values {
            client.eventBus.register(handler, events: events);
        }
    }
    
    open func unregisterEventHandler(_ handler:EventHandler, events:Event...) {
        if let idx = eventHandlers.index(where: { (holder) -> Bool in
            return holder.matches(handler, events: events);
        }) {
            log("removed event handler", handler, "for", events);
            eventHandlers.remove(at: idx);
        } else {
            log("failed to remove event handler", handler, "for", events);
        }
        for client in clients.values {
            client.eventBus.unregister(handler, events: events);
        }
    }
    
    @objc open func accountConfigurationChanged(_ notification: NSNotification) {
        let accountName = notification.userInfo!["account"] as! String;
        let jid = BareJID(accountName);
        updateXmppClientInstance(jid);
    }
    
    @objc open func connectivityChanged(_ notification: NSNotification) {
        self.networkAvailable = notification.userInfo!["connected"] as! Bool;
    }
    
    @objc open func settingsChanged(_ notification: NSNotification) {
        guard let setting = Settings(rawValue: notification.userInfo!["key"] as! String) else {
            return;
        }
        switch setting {
        case .EnableMessageCarbons:
            let value = setting.getBool();
            for client in clients.values {
                if client.state == .connected {
                    let messageCarbonsModule: MessageCarbonsModule? = client.modulesManager.getModule(MessageCarbonsModule.ID);
                    messageCarbonsModule?.setState(value, callback: nil);
                }
            }
        case .StatusMessage:
            sendAutoPresence();
        default:
            break;
        }
    }
    
    open func preformFetch(_ completionHandler: @escaping (UIBackgroundFetchResult)->Void) {
        guard applicationState != .active else {
            print("skipping background fetch as application is active");
            completionHandler(.newData);
            return;
        }
        guard networkAvailable == true else {
            print("skipping background fetch as network is not available");
            completionHandler(.failed);
            return;
        }
        // count connections which needs to resume
        var count = 0;
        for client in clients.values {
            // try to send keepalive to ensure connection is valid
            // if it fails it will try to resume connection
            if client.state != .connected {
                // it looks like this is causing an issue
//                if client.state == .disconnected {
//                    client.login();
//                }
                count += 1;
            } else {
                client.keepalive();
            }
        }
        
        // we need to give connections time to read and process data
        // so event if all are connected lets wait 5secs
        self.backgroundFetchCompletionHandler = completionHandler;
        backgroundFetchTimer = TigaseSwift.Timer(delayInSeconds: count > 0 ? fetchTimeLong : fetchTimeShort, repeats: false, callback: {
            self.backgroundFetchTimedOut();
        });
    }

    fileprivate func backgroundFetchTimedOut() {
        let callback = backgroundFetchCompletionHandler;
        backgroundFetchCompletionHandler = nil;
        if applicationState != .active {
            // do not close here - may be race condtion with opening of an app!
            //disconnectClients(true);
            for client in clients.values {
                if client.state == .connected {
                    if let streamManagement:StreamManagementModule = client.modulesManager.getModule(StreamManagementModule.ID) {
                        streamManagement.sendAck();
                    } else {
                        client.keepalive();
                    }
                }
            }
        }
        callback?(.newData);
    }
    
    fileprivate func increaseBackgroundFetchTimeIfNeeded() {
        let timeout = backgroundFetchTimer?.timeout;
        if timeout != nil && timeout! < fetchTimeLong {
            let callback = backgroundFetchTimer!.callback;
            if callback != nil {
                backgroundFetchTimer?.cancel();
                backgroundFetchTimer = TigaseSwift.Timer(delayInSeconds: min(UIApplication.shared.backgroundTimeRemaining - 5, fetchTimeLong), repeats: false, callback: callback!);
            }
        }
    }
    
    fileprivate func connectClients(_ force: Bool = true) {
        for client in clients.values {
            client.login();
        }
    }
    
    fileprivate func disconnectClients(_ force:Bool = false) {
        for client in clients.values {
            client.disconnect(force);
        }
    }
    
    fileprivate func reconnectMucRooms(_ jid: BareJID) {
        if let client = getClient(jid) {
            guard client.state == .connected else {
                return;
            }
            if let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID) {
                DispatchQueue.global(qos: .background).async {
                    for room in mucModule.roomsManager.getRooms() {
                        if room.state != .joined {
                            _ = room.rejoin();
                        }
                    }
                }
            }
        }
    }
    
    var accepedCertificates = [String]();
    
    fileprivate func validateSslCertificate(_ sessionObject: SessionObject, trust: SecTrust) -> Bool {
        let policy = SecPolicyCreateSSL(false, sessionObject.userBareJid?.domain as CFString?);
        var secTrustResultType = SecTrustResultType.invalid;
        SecTrustSetPolicies(trust, policy);
        SecTrustEvaluate(trust, &secTrustResultType);

        var valid = (secTrustResultType == SecTrustResultType.proceed || secTrustResultType == SecTrustResultType.unspecified);
        if !valid {
            let certCount = SecTrustGetCertificateCount(trust);
            
            if certCount > 0 {
                let cert = SecTrustGetCertificateAtIndex(trust, 0);
                let fingerprint = Digest.sha1.digestToHex(SecCertificateCopyData(cert!) as Data);
                let account = AccountManager.getAccount(sessionObject.userBareJid!.stringValue);
                valid = fingerprint == (account?.serverCertificate?["cert-hash-sha1"] as? String) && ((account?.serverCertificate?["accepted"] as? Bool) ?? false);
            }
            else {
                valid = false;
            }
        }
        return valid;
    }
    
    fileprivate class EventHandlerHolder {
        let handler:EventHandler;
        let events:[Event];
        
        init(handler: EventHandler, events: [Event]) {
            self.handler = handler;
            self.events = events;
        }
        
        func matches(_ handler: EventHandler, events: [Event]) -> Bool {
            return self.handler === handler && self.events == events;
        }
    }
    
    public enum ApplicationState {
        case active
        case inactive
    }
}
