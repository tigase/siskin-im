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
import Martin
import MartinOMEMO
import Combine
import Shared
import TigaseLogging

extension Presence.Show: Codable {
    
}

extension XMPPClient: Hashable {
    
    public static func == (lhs: XMPPClient, rhs: XMPPClient) -> Bool {
        return lhs.connectionConfiguration.userJid == rhs.connectionConfiguration.userJid;
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(connectionConfiguration.userJid);
    }
    
}


open class XmppService {
    
    public static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    public static let AUTHENTICATION_ERROR = Notification.Name("authenticationFailure");
    
    open var fetchTimeShort: TimeInterval = 5;
    open var fetchTimeLong: TimeInterval = 20;
    
    public static let pushServiceJid = JID("push.tigase.im");
    
    public static let instance = XmppService();
    
    public let tasksQueue = KeyedTasksQueue();
    
    fileprivate var creationDate = NSDate();
    fileprivate var fetchClientsWaitingForReconnection: [BareJID] = [];
    fileprivate var fetchStart = NSDate();
        
    let extensions: [XmppServiceExtension] = [MessageEventHandler.instance, BlockedEventHandler.instance, PresenceRosterEventHandler.instance, AvatarEventHandler.instance, MixEventHandler.instance, MucEventHandler.instance, NewFeaturesDetector.instance, PushEventHandler.instance, MeetEventHandler.instance];

    @Published
    open private(set) var applicationState: ApplicationState = .suspended;

    open var onCall: Bool = false {
        didSet {
            // FIXME: handle this properly!!
        }
    }
    
    @Published
    public private(set) var clients: [BareJID: XMPPClient] = [:];
    
    private func client(for account: BareJID) -> XMPPClient? {
        return clients[account];
    }
    
    fileprivate let dispatcher: QueueDispatcher = QueueDispatcher(label: "xmpp_service");
    
    @Published
    var status: Status = Status(show: nil, message: nil, shouldConnect: true, sendInitialPresence: false);
    
    public let expectedStatus = CurrentValueSubject<Status,Never>(Status(show: nil, message: nil, shouldConnect: false, sendInitialPresence: false));
    
    @Published
    fileprivate(set) var currentStatus: Status = Status(show: nil, message: nil, shouldConnect: false, sendInitialPresence: false);
        
    @Published
    public private(set) var connectedClients: Set<XMPPClient> = [];
    
    private var cancellables: Set<AnyCancellable> = [];
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "XmppService");
    fileprivate let dnsSrvResolverCache: DNSSrvResolverCache;
    fileprivate let dnsSrvResolver: DNSSrvResolver;
    fileprivate let streamFeaturesCache: StreamFeaturesCache;
        
    init() {
        self.dnsSrvResolverCache = DNSSrvResolverWithCache.InMemoryCache(store: DNSSrvDiskCache(cacheDirectoryName: "dns-cache"));
        self.dnsSrvResolver = DNSSrvResolverWithCache(resolver: XMPPDNSSrvResolver(directTlsEnabled: true), cache: self.dnsSrvResolverCache);
        self.streamFeaturesCache = StreamFeaturesCache();
        //self.applicationState = UIApplication.shared.applicationState == .active ? .active : .inactive;
                        
        Settings.$statusType.combineLatest(Settings.$statusMessage, { type, messsage in
            Status(show: type, message: (messsage?.isEmpty ?? true) ? nil : messsage, shouldConnect: true, sendInitialPresence: true);
        }).assign(to: \.status, on: self).store(in: &cancellables);
        
        expectedStatus.map({ status in
            return status.shouldConnect
        }).removeDuplicates().sink(receiveValue: { [weak self] available in
            if available {
                self?.connectClients(ignoreCheck: true);
            } else {
                self?.disconnectClients(force: !NetworkMonitor.shared.isNetworkAvailable);
            }
        }).store(in: &cancellables);
        expectedStatus.combineLatest($connectedClients.map({ !$0.isEmpty })).map({ status, connected in
            if !connected {
                return status.with(show: nil);
            }
            return status;
        }).sink(receiveValue: { [weak self] status in self?.currentStatus = status }).store(in: &cancellables);
                
        AccountManager.accountEventsPublisher.receive(on: self.dispatcher.queue).sink(receiveValue: { [weak self] event in
            self?.accountChanged(event: event);
        }).store(in: &cancellables);
    }
    
    private func accountChanged(event: AccountManager.Event) {
        switch event {
        case .enabled(let account, let reconnect):
            guard reconnect else {
                return;
            }
            AccountSettings.reconnectionLocation(for: account.name, value: nil);
            if let client = self.client(for: account.name) {
                // if client exists and is connected, then reconnect it..
                if client.state != .disconnected() {
                    _ = client.disconnect();
                }
            } else {
                let client = self.initializeClient(for: account);
                _ = self.register(client: client, for: account);
                self.connect(client: client, for: account);
            }
        case .disabled(let account), .removed(let account):
            if let client = self.client(for: account.name) {
                let prevState = client.state;
                _ = client.disconnect();
                if prevState == .disconnected() && client.state == .disconnected() {
                    self.unregisterClient(client);
                }
            }
            self.dnsSrvResolverCache.store(for: account.name.domain, result: nil);
        }
    }
    
    open func initialize() {
        for account in AccountManager.getActiveAccounts() {
            let client = self.initializeClient(for: account);
            _ = self.register(client: client, for: account);
        }
        self.$status.combineLatest($applicationState, NetworkMonitor.shared.$isNetworkAvailable, self.$isFetch, { (status, appState, networkAvailble, isFetch) -> Status in
            var newStatus = status;
            if status.show == nil && appState != .suspended {
                newStatus = status.with(show: appState == .inactive ? .xa : .online);
            }
            return newStatus.with(shouldConnect: networkAvailble && ((appState != .suspended) || isFetch), sendInitialPresence: appState != .suspended);
        }).assign(to: \.value, on: expectedStatus).store(in: &cancellables);
    }
    
    open func updateApplicationState(_ state: ApplicationState) {
        //dispatcher.async {
            switch state {
            case .active, .inactive:
                self.applicationState = state;
            case .suspended:
                guard self.applicationState == .inactive else {
                    return;
                }
                self.applicationState = state;
            }
        //}
    }

    open func getClient(for account:BareJID) -> XMPPClient? {
        return dispatcher.sync {
            return self.client(for: account);
        }
    }
    
    private func connectClients(ignoreCheck: Bool) {
        dispatcher.async {
            self.clients.values.forEach { client in
                self.reconnect(client: client, ignoreCheck: ignoreCheck);
            }
        }
    }
    
    private func disconnectClients(force: Bool = false) {
        dispatcher.async {
            self.clients.values.forEach { client in
                _ = client.disconnect(force);
            }
        }
    }
    
    fileprivate func sendKeepAlive() {
        dispatcher.async {
            self.clients.values.forEach { client in
                client.keepalive();
            }
        }
    }
    
    private func reconnect(client: XMPPClient, ignoreCheck: Bool = false) {
        self.dispatcher.sync {
            guard client.state == .disconnected(), let account = AccountManager.getAccount(for: client.userBareJid), account.active, ignoreCheck || self.status.shouldConnect  else {
                return;
            }
            
            self.connect(client: client, for: account);
        }
    }
    
    private func connect(client: XMPPClient, for account: AccountManager.Account) {
        client.connectionConfiguration.credentials = .password(password: account.password ?? "", authenticationName: nil, cache: nil);
        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            if let serverCertificate = account.serverCertificate, serverCertificate.accepted {
                options.sslCertificateValidation = .fingerprint(serverCertificate.details.fingerprintSha1);
            } else {
                options.sslCertificateValidation = .default;
            }
            options.connectionDetails = account.endpoint;
            if let idx = options.networkProcessorProviders.firstIndex(where: { $0 is SSLProcessorProvider }) {
                options.networkProcessorProviders.remove(at: idx);
            }
            options.networkProcessorProviders.append(account.disableTLS13 ? SSLProcessorProvider(supportedTlsVersions: TLSVersion.TLSv1_2...TLSVersion.TLSv1_2) : SSLProcessorProvider());
        });

        client.connectionConfiguration.resource = UIDevice.current.name;
//        switch account.resourceType {
//        case .automatic:
//            client.connectionConfiguration.resource = nil;
//        case .hostname:
//            client.connectionConfiguration.resource = Host.current().localizedName;
//        case .custom:
//            let val = account.resourceName;
//            client.connectionConfiguration.resource = (val == nil || val!.isEmpty) ? nil : val;
//        }
        
        if let pushModule = client.module(.push) as? SiskinPushNotificationsModule {
            pushModule.pushSettings = account.pushSettings;
        }
        
        // for push notifications this needs to be far lower value, ie. 60-90 seconds
        client.modulesManager.module(.streamManagement).maxResumptionTimeout = account.pushNotifications ? 90 : 3600;

        if let streamFeaturesModule: StreamFeaturesModuleWithPipelining = client.modulesManager.moduleOrNil(.streamFeatures) as? StreamFeaturesModuleWithPipelining {
            streamFeaturesModule.enabled = Settings.xmppPipelining;
        }
        
        let connectorEndpoint: ConnectorEndpoint? = AccountSettings.reconnectionLocation(for: account.name);
        client.login(lastSeeOtherHost: connectorEndpoint);
    }
        
    private class ClientCancellables {
        var cancellables: Set<AnyCancellable> = [];
    }

    private var clientCancellables: [BareJID:ClientCancellables] = [:];
    
    private func disconnected(client: XMPPClient) {
        let accountName = client.sessionObject.userBareJid!;
        defer {
            DBChatStore.instance.resetChatStates(for: accountName);
        }
        self.dispatcher.sync {
            let active = AccountManager.getAccount(for: accountName)?.active
            if !(active ?? false) {
                self.unregisterClient(client, removed: active == nil);
            }
        }
        
        
        guard self.status.shouldConnect else {
            return;
        }
        let retry = client.retryNo;
        client.retryNo = retry + 1;
        var timeout = 2.0 * Double(retry) + 0.5;
        if timeout > 16 {
            timeout = 15;
        }
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + timeout) { [weak client] in
            if let c = client {
                self.reconnect(client: c);
            }
        }
    }
    
    private func unregisterClient(_ client: XMPPClient, removed: Bool = false) {
        dispatcher.sync {
            let accountName = client.sessionObject.userBareJid!;
            guard let client = self.clients.removeValue(forKey: accountName) else {
                return;
            }

            self.clientCancellables.removeValue(forKey: accountName);
            
            dispatcher.async {
                if removed {
                    DBRosterStore.instance.clear(for: client)
                    DBChatStore.instance.closeAll(for: accountName);
                    DBChatHistoryStore.instance.removeHistory(for: accountName, with: nil);
                    _ = client;
                }
            }
        }
    }
    
    func forEachClient(_ task: @escaping (XMPPClient)->Void) {
        let clients = dispatcher.sync {
            return Array(self.clients.values);
        }
        clients.forEach(task);
    }
    
    open func backgroundTaskFinished() {
//        guard applicationState != .active else {
//            return;
//        }
        let delegate = UIApplication.shared.delegate as? AppDelegate;
        let unsent = DBChatHistoryStore.instance.countUnsentMessages();
        if unsent > 0 {
            delegate?.notifyUnsentMessages(count: unsent);
        }
    }
    
    private class FetchState {
        private var accountsInProgress: Set<BareJID>;
        private var completionHandler: (()->Void);
        var cancellables: Set<AnyCancellable> = [];
        private let queue = DispatchQueue(label: "FetchStateQueue");
        
        init(accountsInProgress: Set<BareJID>, completionHandler: @escaping ()->Void) {
            self.accountsInProgress = accountsInProgress;
            self.completionHandler = completionHandler;
        }
        
        func completed(for account: BareJID) {
            queue.sync {
                guard accountsInProgress.remove(account) != nil, accountsInProgress.isEmpty else {
                    return;
                }
                completionHandler();
            }
        }
        
        func expired() {
            queue.sync {
                guard !accountsInProgress.isEmpty else {
                    return;
                }
                completionHandler();
            }
        }
    }
    
    private var fetchState: FetchState?;
    
    @Published
    private(set) var isFetch: Bool = false;
    
    open func preformFetch(completionHandler: @escaping (UIBackgroundFetchResult)->Void) {
        guard applicationState != .active else {
            logger.debug("skipping background fetch as application is active");
            completionHandler(.newData);
            return;
        }
        guard NetworkMonitor.shared.isNetworkAvailable == true else {
            logger.debug("skipping background fetch as network is not available");
            completionHandler(.failed);
            return;
        }

        let clients = self.clients.values.filter({ !$0.isConnected });
        guard !clients.isEmpty else {
            completionHandler(.noData);
            return;
        }
        
        let fetchState = FetchState(accountsInProgress: Set(clients.map({ $0.userBareJid })), completionHandler: {
            self.fetchState = nil;
            self.isFetch = false;
            completionHandler(.newData);
        });
        self.fetchState = fetchState;

        MessageEventHandler.eventsPublisher.compactMap({ event in
            guard case .finished(let account, let jid) = event, jid == nil else {
                return nil;
            }
            return account;
        }).sink(receiveValue: { [weak fetchState] account in
            fetchState?.completed(for: account);
        }).store(in: &fetchState.cancellables);

        
        isFetch = true;
    }

    
    open func performFetchExpired() {
        self.fetchState?.expired();
    }
    
    fileprivate func initializeClient(for account: AccountManager.Account) -> XMPPClient {
        let jid = account.name;
        let client = XMPPClient();
        
        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            options.dnsResolver = self.dnsSrvResolver;
            options.networkProcessorProviders.append(SSLProcessorProvider());
            options.connectionTimeout = 15;
        })
        client.connectionConfiguration.userJid = jid;

        _ = client.modulesManager.register(AuthModule());
        _ = client.modulesManager.register(StreamFeaturesModuleWithPipelining(cache: streamFeaturesCache, enabled: false));
        _ = client.modulesManager.register(StreamManagementModule());
        _ = client.modulesManager.register(SaslModule());
        // if you do not want Pipelining you may use StreamFeaturesModule instead StreamFeaturesModuleWithPipelining
        //_ = client.modulesManager.register(StreamFeaturesModule());
        _ = client.modulesManager.register(ResourceBinderModule());
        _ = client.modulesManager.register(SessionEstablishmentModule());
        _ = client.modulesManager.register(DiscoveryModule(identity: DiscoveryModule.Identity(category: "client", type: "pc", name: (Bundle.main.infoDictionary!["CFBundleName"] as! String))));
        _ = client.modulesManager.register(SoftwareVersionModule(version: SoftwareVersionModule.SoftwareVersion(name: Bundle.main.infoDictionary!["CFBundleName"] as! String, version: Bundle.main.infoDictionary!["CFBundleVersion"] as! String, os: UIDevice.current.systemName)));

        _ = client.modulesManager.register(RosterModule(rosterManager: RosterManagerBase(store: DBRosterStore.instance)));

        _ = client.modulesManager.register(VCardTempModule());
        _ = client.modulesManager.register(VCard4Module());
        _ = client.modulesManager.register(PingModule());
        _ = client.modulesManager.register(ClientStateIndicationModule());
        _ = client.modulesManager.register(MobileModeModule());
        
        _ = client.modulesManager.register(BlockingCommandModule());
        
        _ = client.modulesManager.register(PubSubModule());
        _ = client.modulesManager.register(PEPUserAvatarModule());
        _ = client.modulesManager.register(PEPBookmarksModule());

        let messageModule = MessageModule(chatManager: ChatManagerBase(store: DBChatStore.instance));
        _ = client.modulesManager.register(messageModule);

        _ = client.modulesManager.register(MessageCarbonsModule());
        _ = client.modulesManager.register(MessageArchiveManagementModule());

        _ = client.modulesManager.register(MessageDeliveryReceiptsModule()).sendReceived = false;
        _ = client.modulesManager.register(ChatMarkersModule());

        _ = client.modulesManager.register(HttpFileUploadModule());

        _ = client.modulesManager.register(PresenceModule(store: PresenceStore.instance));
        client.modulesManager.register(CapabilitiesModule(cache: DBCapabilitiesCache.instance, additionalFeatures: [.lastMessageCorrection, .messageRetraction]));

        client.modulesManager.register(CustomMucModule(roomManager: RoomManagerBase(store: DBChatStore.instance)));
                                            
         client.modulesManager.register(MixModule(channelManager: ChannelManagerBase(store: DBChatStore.instance)));
         
         _ = client.modulesManager.register(AdHocCommandsModule());
        
        _ = client.modulesManager.register(SiskinPushNotificationsModule(defaultPushServiceJid: XmppService.pushServiceJid, provider: SiskinPushNotificationsModuleProvider()));
        let jingleModule = client.modulesManager.register(JingleModule(sessionManager: JingleManager.instance));
        jingleModule.register(transport: Jingle.Transport.ICEUDPTransport.self, features: [Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:dtls:0"]);
        jingleModule.register(description: Jingle.RTP.Description.self, features: ["urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"]);
        jingleModule.supportsMessageInitiation = true;
        _ = client.modulesManager.register(ExternalServiceDiscoveryModule());
        client.modulesManager.register(MeetModule());
        _ = client.modulesManager.register(InBandRegistrationModule());
        // TODO: restore support for caching salted password
//        ScramMechanism.setSaltedPasswordCache(AccountManager.saltedPasswordCache, sessionObject: client.sessionObject);
        
        let signalStorage = OMEMOStoreWrapper(context: client.context);
        let signalContext = SignalContext(withStorage: signalStorage)!;
        signalStorage.setup(withContext: signalContext);
        _ = client.modulesManager.register(OMEMOModule(aesGCMEngine: OpenSSL_AES_GCM_Engine(), signalContext: signalContext, signalStorage: signalStorage));
        
        return client;
    }
    

    fileprivate func register(client: XMPPClient, for account: AccountManager.Account) -> XMPPClient {
        return self.dispatcher.sync {
            let clientCancellables = ClientCancellables();
            self.clientCancellables[account.name] = clientCancellables;
                        
            client.$state.subscribe(account.state).store(in: &clientCancellables.cancellables);
            client.$state.dropFirst().sink(receiveValue: { state in self.changedState(state, for: client) }).store(in: &clientCancellables.cancellables);
                    
            for ext in extensions {
                ext.register(for: client, cancellables: &clientCancellables.cancellables);
            }
                                    
            client.$state.combineLatest($applicationState).sink(receiveValue: { [weak client] (clientState, applicationState) in
                if clientState == .connected() {
                    _ = client?.module(.csi).setState(applicationState == .active);
                }
            }).store(in: &clientCancellables.cancellables);
                    
            self.clients[account.name] = client;
            return client;
        }
    }
    
    private func changedState(_ state: XMPPClient.State, for client: XMPPClient) {
        switch state {
        case .connected:
            self.dispatcher.async {
                self.connectedClients.insert(client);
            }
        case .disconnected(let reason):
            self.dispatcher.async {
                self.connectedClients.remove(client);
            }
            AccountSettings.reconnectionLocation(for: client.userBareJid, value: nil);
            switch reason {
            case .sslCertError(let trust):
                let certData = ServerCertificateInfo(trust: trust);
                if var account = AccountManager.getAccount(for: client.userBareJid) {
                    account.active = false;
                    account.serverCertificate = certData;
                    try? AccountManager.save(account: account);
                    NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: client.userBareJid, userInfo: ["account": client.userBareJid.stringValue, "cert-name": certData.details.name, "cert-hash-sha1": certData.details.fingerprintSha1, "issuer-name": certData.issuer?.name, "issuer-hash-sha1": certData.issuer?.fingerprintSha1]);
                }
            case .authenticationFailure(let err):
                if let error = err as? SaslError {
                    switch error {
                    case .aborted, .temporary_auth_failure:
                        // those are temporary errors, we shoud retry
                        break;
                    default:
                        reportSaslError(on: client.userBareJid, error: error);
                    }
                } else {
                    reportSaslError(on: client.userBareJid, error: .not_authorized);
                }
            case .none:
                AccountSettings.reconnectionLocation(for: client.userBareJid, value: client.connector?.currentEndpoint);
            default:
                break;
            }
            self.disconnected(client: client);
        default:
            break;
        }
    }
    
    private func reportSaslError(on accountJID: BareJID, error: SaslError) {
        guard var account = AccountManager.getAccount(for: accountJID) else {
            return;
        }
        account.active = false;
        try? AccountManager.save(account: account);
        NotificationCenter.default.post(name: XmppService.AUTHENTICATION_ERROR, object: accountJID, userInfo: ["error": error]);
    }
        
    public enum ApplicationState {
        case active
        case inactive
        case suspended
    }
    
    public struct Status: Codable, Equatable {
        public static func == (lhs: XmppService.Status, rhs: XmppService.Status) -> Bool {
            guard lhs.shouldConnect == rhs.shouldConnect else {
                return false;
            }
            
            if (lhs.show == nil && rhs.show == nil) {
                return (lhs.message ?? "") == (rhs.message ?? "");
            } else if let ls = lhs.show, let rs = rhs.show {
                return ls == rs && (lhs.message ?? "") == (rhs.message ?? "");
            } else {
                return false;
            }
        }
        
        let show: Presence.Show?;
        let message: String?;
        let shouldConnect: Bool;
        let sendInitialPresence: Bool;
        
        init(show: Presence.Show?, message: String?, shouldConnect: Bool, sendInitialPresence: Bool) {
            self.show = show;
            self.message = message;
            self.shouldConnect = shouldConnect;
            self.sendInitialPresence = sendInitialPresence;
        }
        
        func with(show: Presence.Show?) -> Status {
            return Status(show: show, message: self.message, shouldConnect: shouldConnect, sendInitialPresence: sendInitialPresence);
        }
        
        func with(message: String?) -> Status {
            return Status(show: self.show, message: message, shouldConnect: shouldConnect, sendInitialPresence: sendInitialPresence);
        }

        func with(show: Presence.Show?, message: String?) -> Status {
            return Status(show: show, message: message, shouldConnect: shouldConnect, sendInitialPresence: sendInitialPresence);
        }
        
        func with(shouldConnect: Bool, sendInitialPresence: Bool) -> Status {
            return Status(show: show, message: message, shouldConnect: shouldConnect, sendInitialPresence: sendInitialPresence);
        }
        
        func toDict() -> [String : Any?] {
            var dict: [String: Any?] = [:];
            if message != nil {
                dict["message"] = message;
            }
            if show != nil {
                dict["show"] = show?.rawValue;
            }
            return dict;
        }
    }
}
