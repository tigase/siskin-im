//
// XmppService.swift
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
import Shared
import TigaseSwift
import TigaseSwiftOMEMO

open class XmppService: Logger, EventHandler {
    
    public static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    public static let AUTHENTICATION_FAILURE = Notification.Name("authenticationFailure");
    public static let CONTACT_PRESENCE_CHANGED = Notification.Name("contactPresenceChanged");
    public static let PRESENCE_AUTHORIZATION_REQUEST = Notification.Name("presenceAuthorizationRequest");
    public static let ACCOUNT_STATE_CHANGED = Notification.Name("accountStateChanged");
    public static let MUC_ROOM_INVITATION = Notification.Name("mucRoomInvitation");
    
    open var fetchTimeShort: TimeInterval = 5;
    open var fetchTimeLong: TimeInterval = 20;
    
    public static let pushServiceJid = JID("push.tigase.im");
    
    public static let instance = XmppService();
    public let tasksQueue = KeyedTasksQueue();
    fileprivate static let CONNECTION_RETRY_NO_KEY = "CONNECTION_RETRY_NO_KEY";
    
    fileprivate var creationDate = NSDate();
    fileprivate var fetchClientsWaitingForReconnection: [BareJID] = [];
    fileprivate var fetchStart = NSDate();
        
    #if targetEnvironment(simulator)
    fileprivate let eventHandlers: [XmppServiceEventHandler] = [NewFeaturesDetector(), MessageEventHandler(), MucEventHandler.instance, PresenceRosterEventHandler(), AvatarEventHandler(), DiscoEventHandler(), PushEventHandler.instance, BlockedEventHandler.instance];
    #else
    fileprivate let eventHandlers: [XmppServiceEventHandler] = [NewFeaturesDetector(), MessageEventHandler(), MucEventHandler.instance, PresenceRosterEventHandler(), AvatarEventHandler(), DiscoEventHandler(), PushEventHandler.instance, JingleManager.instance, BlockedEventHandler.instance];
    #endif
    
    public let dbCapsCache: DBCapabilitiesCache;
    public let dbChatStore: DBChatStore;
    public let dbChatHistoryStore: DBChatHistoryStore;
    fileprivate let dbRosterStore: DBRosterStore;
    public let dbVCardsCache: DBVCardsCache;
    fileprivate let avatarStore: AvatarStore;
    open var applicationState: ApplicationState = .inactive {
        didSet {
            if oldValue != applicationState {
                applicationStateChanged();
            }
            if applicationState != .active {
                AvatarManager.instance.clearCache();
            }
        }
    }
    
    fileprivate let reachability: Reachability;

    fileprivate var clients = [BareJID: XMPPClient]();
    fileprivate let dispatcher: QueueDispatcher = QueueDispatcher(label: "xmpp_service_clients", attributes: [.concurrent]);
    
    fileprivate let dnsSrvResolverCache: DNSSrvResolverCache;
    fileprivate let dnsSrvResolver: DNSSrvResolver;
    fileprivate var networkAvailable:Bool = false {
        didSet {
            if networkAvailable {
                if !oldValue {
                    if applicationState == .active {
                        connectClients();
                    }
                } else {
                    keepalive();
                }
            } else if !networkAvailable && oldValue {
                disconnectClients(force: true);
            }
        }
    }
    fileprivate let streamFeaturesCache: StreamFeaturesCache;
        
    convenience override init() {
        self.init(dbConnection: DBConnection.main);
    }
    
    fileprivate init(dbConnection:DBConnection) {
        self.dnsSrvResolverCache = DNSSrvResolverWithCache.InMemoryCache(store: DNSSrvDiskCache(cacheDirectoryName: "dns-cache"));
        self.dnsSrvResolver = DNSSrvResolverWithCache(resolver: XMPPDNSSrvResolver(), cache: self.dnsSrvResolverCache);
        self.streamFeaturesCache = StreamFeaturesCache();
        self.dbCapsCache = DBCapabilitiesCache(dbConnection: dbConnection);
        self.dbChatStore = DBChatStore.instance;
        self.dbChatHistoryStore = DBChatHistoryStore(dbConnection: dbConnection);
        self.dbRosterStore = DBRosterStore(dbConnection: dbConnection);
        self.dbVCardsCache = DBVCardsCache(dbConnection: dbConnection);
        self.avatarStore = AvatarStore(dbConnection: dbConnection);
        self.reachability = Reachability();
        self.networkAvailable = false;
        self.applicationState = UIApplication.shared.applicationState == .active ? .active : .inactive;
        
        super.init();
        
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.accountConfigurationChanged), name: AccountManager.ACCOUNT_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.connectivityChanged), name: Reachability.CONNECTIVITY_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.settingsChanged), name: Settings.SETTINGS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(XmppService.messageSynchronizationFinished), name: MessageEventHandler.MESSAGE_SYNCHRONIZATION_FINISHED, object: nil);
    }
    
    open func initialize() {
        for accountName in AccountManager.getAccounts() {
            if let client = self.initializeClient(jid: accountName) {
                _ = self.register(client: client, for: accountName);
            }
        }
        networkAvailable = reachability.isConnectedToNetwork();
    }
    
    open func getClients(filter: ((XMPPClient)->Bool)? = nil) -> [XMPPClient] {
        return dispatcher.sync {
            return self.clients.values.filter(filter ?? { (client) -> Bool in
                return true;
            });
        }
    }

    open func getClient(for account:BareJID) -> XMPPClient? {
        return dispatcher.sync {
            return self.clients[account];
        }
    }

    open func getClient(forJid account:BareJID) -> XMPPClient? {
        return dispatcher.sync {
            return self.clients[account];
        }
    }
    
    open func handle(event: Event) {
        switch event {
        case let e as SocketConnector.CertificateErrorEvent:
            // at first let's disable account so it will not try to reconnect
            // until user will take action
            
            let certData = SslCertificateInfo(trust: e.trust!);

            var certInfo: [String: Any] = [:];
            certInfo["cert-name"] = certData.details.name;
            certInfo["cert-hash-sha1"] = certData.details.fingerprintSha1;
            certInfo["issuer-name"] = certData.issuer?.name;
            certInfo["issuer-hash-sha1"] = certData.issuer?.fingerprintSha1;
            
            print("cert info =", certInfo);
            
            if let account = AccountManager.getAccount(for: e.sessionObject.userBareJid!) {
                account.active = false;
                account.serverCertificate = certInfo;
                AccountManager.save(account: account);
            }
            
            var info = certInfo;
            info["account"] = e.sessionObject.userBareJid!.stringValue as NSString;
            AccountSettings.LastError(e.sessionObject.userBareJid!).set(string: "cert");
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: self, userInfo: info);
            }
        case let e as SocketConnector.ConnectedEvent:
            if let jid = e.sessionObject.userBareJid {
                NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account":jid.stringValue]);
            }
        case let e as SocketConnector.DisconnectedEvent:
            networkAvailable = reachability.isConnectedToNetwork();
            if let jid = e.sessionObject.userBareJid {
                if let client = self.getClient(forJid: jid) {
                    if e.clean, let connDetails = e.connectionDetails, let json = try? JSONEncoder().encode(connDetails) {
                        AccountSettings.reconnectionLocation(jid).set(string: json.base64EncodedString());
                    } else {
                        AccountSettings.reconnectionLocation(jid).set(string: nil);
                    }
                    
                    disconnected(client: client);
                }
                DispatchQueue.global(qos: .default).async {
                    NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account":jid.stringValue]);
                }
            }
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            if e.features.contains(MessageCarbonsModule.MC_XMLNS) {
                if let messageCarbonsModule: MessageCarbonsModule = getClient(forJid: e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) {
                    if Settings.enableMessageCarbons.getBool() {
                        messageCarbonsModule.enable();
                    }
                }
            }
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            let account = e.sessionObject.userBareJid!;

            let client = getClient(forJid: e.sessionObject.userBareJid!);
            client?.sessionObject.setProperty(XmppService.CONNECTION_RETRY_NO_KEY, value: nil);
            DispatchQueue.global(qos: .default).async {
                NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account":e.sessionObject.userBareJid!.stringValue]);
            }
            if let c = client {
                let end = Date().timeIntervalSinceReferenceDate
                let start = c.sessionObject.getProperty("startTime", defValue: Date()).timeIntervalSinceReferenceDate;
                print("connected", c.sessionObject.userBareJid!, "from:", start, "to:", end, "in:", end-start);
            }
            if applicationState == .inactive {
                let csiModule: ClientStateIndicationModule? = client?.modulesManager.getModule(ClientStateIndicationModule.ID);
                if csiModule != nil && csiModule!.available {
                    _ = csiModule!.setState(applicationState == .active);
                }
                else if let mobileModeModule: MobileModeModule = client?.modulesManager.getModule(MobileModeModule.ID) {
                    mobileModeModule.enable();
                }
            }
        case let e as AuthModule.AuthFailedEvent:
            if e.error != SaslError.aborted && e.error != SaslError.temporary_auth_failure {
                if let account = AccountManager.getAccount(for: e.sessionObject.userBareJid!) {
                    account.active = false;
                    AccountManager.save(account: account);
                }
                var info: [String: AnyObject] = [:];
                info["account"] = e.sessionObject.userBareJid!.stringValue as NSString;
                info["auth-error-type"] = e.error.rawValue as NSString;
                AccountSettings.LastError(e.sessionObject.userBareJid!).set(string: "auth");
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: XmppService.AUTHENTICATION_FAILURE, object: self, userInfo: info);
                }
            }
        case let e as StreamManagementModule.ResumedEvent:
            let client = getClient(forJid: e.sessionObject.userBareJid!);
            client?.sessionObject.setProperty(XmppService.CONNECTION_RETRY_NO_KEY, value: nil);
            let csiModule: ClientStateIndicationModule? = client?.modulesManager.getModule(ClientStateIndicationModule.ID);
            if csiModule != nil && csiModule!.available {
                _ = csiModule!.setState(applicationState == .active);
            }
            else if let mobileModeModule: MobileModeModule = client?.modulesManager.getModule(MobileModeModule.ID) {
                _ = mobileModeModule.setState(applicationState == .inactive);
            }
            
            // here we should notify messenger that connection was resumed and we can end soon
            if client != nil {
                self.connected(client: client!);
            }
        default:
            log("received unsupported event", event);
        }
    }
    
    open func keepalive() {
        forEachClient { (client) in
            client.keepalive();
        }
    }
    
    fileprivate func applicationStateChanged() {
        sendAutoPresence();
        forEachClient { (client) in
            if client.state == .connected {
                let csiModule: ClientStateIndicationModule? = client.modulesManager.getModule(ClientStateIndicationModule.ID);
                if csiModule != nil && csiModule!.available {
                    _ = csiModule!.setState(self.applicationState == .active);
                }
                else if let mobileModeModule: MobileModeModule = client.modulesManager.getModule(MobileModeModule.ID) {
                    _ = mobileModeModule.setState(self.applicationState == .inactive);
                }
            }
        }
        if applicationState == .active {
            connectClients();
            forEachClient { client in
                client.sessionObject.setProperty(XmppService.CONNECTION_RETRY_NO_KEY, value: nil);
                if client.state == .connected && self.isFetch {
                    if let mcModule: MessageCarbonsModule = client.modulesManager.getModule(MessageCarbonsModule.ID), mcModule.isAvailable && Settings.enableMessageCarbons.bool() {
                        mcModule.enable();
                    }
                }
//                if client.state == .disconnected { // && client.pushNotificationsEnabled {
//                    client.login();
//                    //updateXmppClientInstance(forJid: client.sessionObject.userBareJid!);
//                }
            }
        }
    }
    
    fileprivate func sendAutoPresence() {
        forEachClient { (client) in
            if client.state == .connected {
                if let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) {
                    presenceModule.setPresence(show: .online, status: nil, priority: nil);
                }
            }
        }
    }
    
    @objc open func accountConfigurationChanged(_ notification: NSNotification) {
        guard let account = notification.object as? AccountManager.Account else {
            return;
        }
        
        let active = AccountManager.getAccount(for: account.name)?.active ?? false;
        
        guard active else {
            dispatcher.async {
                guard let client = self.clients[account.name] else {
                    return;
                }
                
                self.disconnect(client: client);
                self.dnsSrvResolverCache.store(for: account.name.domain, result: nil);
            }
            return;
        }
        
        dispatcher.async(flags: .barrier) {
            if let client = self.clients[account.name] {
                self.disconnect(client: client);
            } else if let client = self.initializeClient(jid: account.name) {
                self.register(client: client, for: account.name);
                self.connect(client: client);
            }
        }
    }
    
    @objc open func connectivityChanged(_ notification: NSNotification) {
        guard let reachability = notification.object as? Reachability else {
            return;
        }
        self.networkAvailable = reachability.isConnectedToNetwork();
    }
    
    @objc open func settingsChanged(_ notification: NSNotification) {
        guard let setting = Settings(rawValue: notification.userInfo!["key"] as! String) else {
            return;
        }
        switch setting {
        case .enableMessageCarbons:
            let value = setting.getBool();
            forEachClient { (client) in
                if client.state == .connected {
                    let messageCarbonsModule: MessageCarbonsModule? = client.modulesManager.getModule(MessageCarbonsModule.ID);
                    messageCarbonsModule?.setState(value, callback: nil);
                }
            }
        case .StatusMessage, .StatusType:
            sendAutoPresence();
        case .DeviceToken:
            let newDeviceId = notification.userInfo?["newValue"] as? String;
            // FIXME: do something about it? is it needed?
//            forEachClient { (client) in
//                if let pushModule: TigasePushNotificationsModule = client.modulesManager.getModule(PushNotificationsModule.ID) {
//                    pushModule.deviceId = newDeviceId;
//                }
//            }
        default:
            break;
        }
    }
    
    func forEachClient(_ task: @escaping (XMPPClient)->Void) {
        dispatcher.async {
            self.clients.values.forEach(task);
        }
    }
    
    open func backgroundTaskFinished() {
        guard applicationState != .active else {
            return;
        }
        let group = DispatchGroup();
        group.enter();
        let delegate = UIApplication.shared.delegate as? AppDelegate;
        DBChatHistoryStore.instance.countUnsentMessages() { unsent in
            guard unsent > 0  else {
                group.leave();
                return;
            }
            
            delegate?.notifyUnsentMessages(count: unsent);
            group.leave();
        }
        // we should handle this concurrently!!
        dispatcher.sync {
            for client in self.clients.values {
                group.enter();
                self.dispatcher.async {
                    self.disconnect(client: client) {
                        print("leaving group by", client.sessionObject.userBareJid!);
                        group.leave();
                    }
                }
            }
        }
        group.wait();
    }
    
    fileprivate var fetchGroup: DispatchGroup? = nil;
    fileprivate var fetchCompletionHandler: ((UIBackgroundFetchResult)->Void)? = nil;
    
    fileprivate(set) var isFetch: Bool = false {
        didSet {
            dispatcher.sync {
                clients.values.forEach { (client) in
                    if let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) {
                        presenceModule.initialPresence = !isFetch;
                    }
                }
            }
        }
    }
    
    fileprivate var fetchingFor: [BareJID] = [];
    
    open func preformFetch(completionHandler: @escaping (UIBackgroundFetchResult)->Void) {
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
        
        isFetch = true;
        fetchingFor = [];
        
        fetchGroup = DispatchGroup();
        dispatcher.sync {
            for client in clients.values {
                // try to send keepalive to ensure connection is valid
                // if it fails it will try to resume connection
                if client.state != .connected {
                    if client.state == .disconnected && AccountSettings.messageSyncAuto(client.sessionObject.userBareJid!).bool() {
                        fetchGroup?.enter();
                        fetchingFor.append(client.sessionObject.userBareJid!);
                        print("reconnecting client:", client.sessionObject.userBareJid!);
                        if !self.connect(client: client) {
                            self.fetchEnded(for: client.sessionObject.userBareJid!);
                        }
                    }
                } else {
                    client.keepalive();
                }
            }
            fetchGroup?.notify(queue: DispatchQueue.main) {
                self.isFetch = false;
                self.fetchGroup = nil;
                completionHandler(.newData);
            }
        }
    }
    
    open func performFetchExpired() {
        guard applicationState == .inactive, let fetchGroup = self.fetchGroup else {
            return;
        }
        
        dispatcher.sync {
            for client in clients.values {
                if client.state == .connected || client.state == .connecting {
                    self.disconnect(client: client) {
                        self.fetchEnded(for: client.sessionObject.userBareJid!);
                    }
                }
            }
        }
    }
    
    fileprivate func fetchEnded(for account: BareJID) {
        dispatcher.async {
            if let idx = self.fetchingFor.firstIndex(of: account) {
                self.fetchingFor.remove(at: idx);
                self.fetchGroup?.leave();
            }
        }
    }
    
    @objc open func messageSynchronizationFinished(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID else {
            return;
        }
        print("message synchronization finished for account:", account)
        if self.applicationState == .inactive, let client = getClient(for: account) {
            disconnect(client: client) {
                self.fetchEnded(for: account);
            }
            return;
        } else {
            self.fetchEnded(for: account);
        }
    }
    
    fileprivate func connected(client: XMPPClient) {
        let account = client.sessionObject.userBareJid!;
        DispatchQueue.global(qos: .default).async {
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account": account.stringValue]);
        }
    }
    
    fileprivate func disconnected(client: XMPPClient) {
        let account = client.sessionObject.userBareJid!;
        self.fetchEnded(for: account);
        DispatchQueue.global(qos: .default).async {
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account": account.stringValue]);
        }
        
        let active = AccountManager.getAccount(for: client.sessionObject.userBareJid!)?.active ?? false;
        guard active else {
            self.unregisterClient(for: client.sessionObject.userBareJid!);
            return;
        }
        
        guard self.applicationState == .active else {
            return;
        }
        
        let retryNo = client.sessionObject.getProperty(XmppService.CONNECTION_RETRY_NO_KEY, defValue: 0) + 1;
        client.sessionObject.setProperty(XmppService.CONNECTION_RETRY_NO_KEY, value: retryNo);
        connect(client: client);
    }
    
    fileprivate func connectClients() {
        guard self.networkAvailable else {
            return;
        }
        dispatcher.async {
            self.clients.values.forEach { client in
                self.connect(client: client);
            }
        }
    }
    
    fileprivate func disconnectClients(force:Bool = false) {
        dispatcher.async {
            self.clients.values.forEach { client in
                self.disconnect(client: client, force: force);
            }
        }
    }
    
    @discardableResult
    fileprivate func connect(client: XMPPClient) -> Bool {
        guard let account = AccountManager.getAccount(for: client.sessionObject.userBareJid!), account.active, self.networkAvailable, client.state == .disconnected else {
            return false;
        }
        
        if let seeOtherHostStr = AccountSettings.reconnectionLocation(account.name).getString(), let seeOtherHost = Data(base64Encoded: seeOtherHostStr), let val = try? JSONDecoder().decode(XMPPSrvRecord.self, from: seeOtherHost) {
            client.sessionObject.setUserProperty(SocketConnector.SEE_OTHER_HOST_KEY, value: val);
        }

        client.connectionConfiguration.setUserPassword(account.password);
        SslCertificateValidator.setAcceptedSslCertificate(client.sessionObject, fingerprint: ((account.serverCertificate?["accepted"] as? Bool) ?? false) ? (account.serverCertificate?["cert-hash-sha1"] as? String) : nil);

        // Setting resource to use - using device name
        client.sessionObject.setUserProperty(SessionObject.RESOURCE, value: UIDevice.current.name);

        // Setting software name, version and OS name
        client.sessionObject.setUserProperty(SoftwareVersionModule.NAME_KEY, value: Bundle.main.infoDictionary!["CFBundleName"] as! String);
        client.sessionObject.setUserProperty(SoftwareVersionModule.VERSION_KEY, value: Bundle.main.infoDictionary!["CFBundleVersion"] as! String);
        client.sessionObject.setUserProperty(SoftwareVersionModule.OS_KEY, value: UIDevice.current.systemName);
        // need to establish connection in 1 sec.
        client.sessionObject.setUserProperty(SocketConnector.CONNECTION_TIMEOUT, value: 15.0);
        
        if let pushModule: SiskinPushNotificationsModule = client.modulesManager.getModule(SiskinPushNotificationsModule.ID) {
            pushModule.pushSettings = account.pushSettings;
            pushModule.shouldEnable = account.pushNotifications;
        }
        if let smModule: StreamManagementModule = client.modulesManager.getModule(StreamManagementModule.ID) {
            // for push notifications this needs to be far lower value, ie. 60-90 seconds
            smModule.maxResumptionTimeout = account.pushNotifications ? 90 : 3600;
        }
        if let streamFeaturesModule: StreamFeaturesModuleWithPipelining = client.modulesManager.getModule(StreamFeaturesModuleWithPipelining.ID) {
            streamFeaturesModule.enabled = Settings.XmppPipelining.getBool();
        }

        client.login();
        
        DispatchQueue.global(qos: .default).async {
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account": account.name.stringValue]);
        }
        return true;
    }
    
    fileprivate func disconnect(client: XMPPClient, force: Bool = false, completionHandler: (()->Void)? = nil) {
        client.disconnect(force, completionHandler: completionHandler);
        let account = client.sessionObject.userBareJid!;
        DispatchQueue.global(qos: .default).async {
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATE_CHANGED, object: self, userInfo: ["account": account.stringValue]);
        }
    }
    
    fileprivate func initializeClient(jid: BareJID) -> XMPPClient? {
        guard AccountManager.getAccount(for: jid)?.active ?? false else {
            return nil;
        }

        let client = XMPPClient();
        client.connectionConfiguration.setUserJID(jid);
        client.keepaliveTimeout = 0;
        registerModules(client);
        
        SslCertificateValidator.registerSslCertificateValidator(client.sessionObject);
        return client;
    }
    
    fileprivate func register(client: XMPPClient, for account: BareJID) -> XMPPClient {
        self.dispatcher.sync(flags: .barrier) {
            self.registerEventHandlers(client);
            self.clients[account] = client;
        }
        if let messageModule: MessageModule = client.modulesManager.getModule(MessageModule.ID) {
            ((messageModule.chatManager as! DefaultChatManager).chatStore as! DBChatStoreWrapper).initialize();
        }
        return client;
    }
    
    fileprivate func unregisterClient(for account: BareJID) {
        guard let client = self.dispatcher.sync(flags: .barrier, execute: {  return self.clients.removeValue(forKey: account) }) else {
            return;
        }
        if let messageModule: MessageModule = client.modulesManager.getModule(MessageModule.ID) {
            ((messageModule.chatManager as! DefaultChatManager).chatStore as! DBChatStoreWrapper).deinitialize();
        }
        AccountSettings.reconnectionLocation(account).set(string: nil);
        unregisterEventHandlers(client);
    }
            
        fileprivate func registerModules(_ client:XMPPClient) {
            client.sessionObject.dnsSrvResolver = self.dnsSrvResolver;
            _ = client.modulesManager.register(StreamManagementModule());
            _ = client.modulesManager.register(AuthModule());
            _ = client.modulesManager.register(StreamFeaturesModuleWithPipelining(cache: streamFeaturesCache, enabled: false));
            // if you do not want Pipelining you may use StreamFeaturesModule instead StreamFeaturesModuleWithPipelining
            //_ = client.modulesManager.register(StreamFeaturesModule());
            _ = client.modulesManager.register(SaslModule());
            _ = client.modulesManager.register(ResourceBinderModule());
            _ = client.modulesManager.register(SessionEstablishmentModule());
            _ = client.modulesManager.register(DiscoveryModule());
            _ = client.modulesManager.register(SoftwareVersionModule());
            _ = client.modulesManager.register(VCardTempModule());
            _ = client.modulesManager.register(VCard4Module());
            _ = client.modulesManager.register(ClientStateIndicationModule());
            _ = client.modulesManager.register(MobileModeModule());
            _ = client.modulesManager.register(PingModule());
            _ = client.modulesManager.register(PubSubModule());
            _ = client.modulesManager.register(PEPUserAvatarModule());
            _ = client.modulesManager.register(PEPBookmarksModule());
            let rosterModule =  client.modulesManager.register(RosterModule());
            rosterModule.rosterStore = DBRosterStoreWrapper(sessionObject: client.sessionObject, store: dbRosterStore);
            rosterModule.versionProvider = dbRosterStore;
            _ = client.modulesManager.register(PresenceModule());
            let messageModule = client.modulesManager.register(MessageModule());
            let chatManager = CustomChatManager(context: client.context, chatStore: DBChatStoreWrapper(sessionObject: client.sessionObject));
            messageModule.chatManager = chatManager;
            _ = client.modulesManager.register(MessageCarbonsModule());
            _ = client.modulesManager.register(MessageArchiveManagementModule());
            let mucModule = MucModule();
            mucModule.roomsManager = DBRoomsManager(store: dbChatStore);
            _ = client.modulesManager.register(mucModule);
            _ = client.modulesManager.register(AdHocCommandsModule());
            _ = client.modulesManager.register(SiskinPushNotificationsModule(defaultPushServiceJid: XmppService.pushServiceJid, provider: SiskinPushNotificationsModuleProvider()));
            _ = client.modulesManager.register(HttpFileUploadModule());
            _ = client.modulesManager.register(MessageDeliveryReceiptsModule());
            _ = client.modulesManager.register(BlockingCommandModule());
            #if targetEnvironment(simulator)
            #else
            let jingleModule = client.modulesManager.register(JingleModule(sessionManager: JingleManager.instance));
            jingleModule.register(transport: Jingle.Transport.ICEUDPTransport.self, features: [Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:dtls:0"]);
            jingleModule.register(description: Jingle.RTP.Description.self, features: ["urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"]);
            #endif
            _ = client.modulesManager.register(InBandRegistrationModule());
            let capsModule = client.modulesManager.register(CapabilitiesModule());
            capsModule.cache = dbCapsCache;
            ScramMechanism.setSaltedPasswordCache(AccountManager.saltedPasswordCache, sessionObject: client.sessionObject);
            
            let signalStorage = OMEMOStoreWrapper(context: client.context);
            let signalContext = SignalContext(withStorage: signalStorage)!;
            signalStorage.setup(withContext: signalContext);
            _ = client.modulesManager.register(OMEMOModule(aesGCMEngine: OpenSSL_AES_GCM_Engine(), signalContext: signalContext, signalStorage: signalStorage));
            
            client.sessionObject.setUserProperty(SessionObject.COMPRESSION_DISABLED, value: true);
            client.modulesManager.initIfRequired();
        }
        
        fileprivate func registerEventHandlers(_ client:XMPPClient) {
            client.eventBus.register(handler: self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE, AuthModule.AuthFailedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE);
            for handler in self.eventHandlers {
                client.eventBus.register(handler: handler, for: handler.events);
            }
        }
        
        fileprivate func unregisterEventHandlers(_ client:XMPPClient) {
            client.eventBus.unregister(handler: self, for: SocketConnector.ConnectedEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE, AuthModule.AuthFailedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE);
            for handler in eventHandlers {
                client.eventBus.unregister(handler: handler, for: handler.events);
            }
        }

        
    public enum ApplicationState {
        case active
        case inactive
    }
}
