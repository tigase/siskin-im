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

public class XmppService: Logger, EventHandler {
    
    public var fetchTimeShort: NSTimeInterval = 5;
    public var fetchTimeLong: NSTimeInterval = 25;
    
    private var creationDate = NSDate();
    
    private let dbConnection:DBConnection;
    public var avatarManager:AvatarManager!;
    public let dbChatStore:DBChatStore;
    public let dbChatHistoryStore:DBChatHistoryStore;
    public let dbRosterStore:DBRosterStore;
    public let dbVCardsCache:DBVCardsCache;
    
    public var applicationState:ApplicationState {
        didSet {
            if oldValue != applicationState {
                applicationStateChanged();
            }
        }
    }
    
    private let reachability:Reachability;
    
    private var clients = [BareJID:XMPPClient]();
    
    private var eventHandlers:[EventHandlerHolder] = [];
    
    private var networkAvailable:Bool {
        didSet {
            if networkAvailable && !oldValue {
                connectClients();
            } else {
                disconnectClients(true);
            }
        }
    }
    
    private var backgroundFetchCompletionHandler: ((UIBackgroundFetchResult)->Void)?;
    private var backgroundFetchTimer: Timer?;
    
    init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        self.dbChatStore = DBChatStore(dbConnection: dbConnection);
        self.dbChatHistoryStore = DBChatHistoryStore(dbConnection: dbConnection);
        self.dbRosterStore = DBRosterStore(dbConnection: dbConnection);
        self.dbVCardsCache = DBVCardsCache(dbConnection: dbConnection);
        self.reachability = Reachability();
        self.networkAvailable = false;
        self.applicationState = UIApplication.sharedApplication().applicationState == .Active ? .active : .inactive;

        super.init();
        self.avatarManager = AvatarManager(xmppService: self);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(XmppService.accountConfigurationChanged), name:"accountConfigurationChanged", object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(XmppService.connectivityChanged), name: Reachability.CONNECTIVITY_CHANGED, object: nil);
        networkAvailable = reachability.isConnectedToNetwork();
    }
    
    public func updateXmppClientInstance() {
        for account in AccountManager.getAccounts() {
            updateXmppClientInstance(BareJID(account));
        }
    }
    
    public func updateXmppClientInstance(userJid:BareJID) {
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
        } else {
            if client?.state != SocketConnector.State.disconnected {
                client?.disconnect();
                return;
            }
            
            if password == nil || config == nil || config?.active != true {
                clients.removeValueForKey(userJid);
                unregisterEventHandlers(client!);
                return;
            }
        }
        
        client?.connectionConfiguration.setUserJID(userJid);
        client?.connectionConfiguration.setUserPassword(password);
        
        clients[userJid] = client;
        
        if networkAvailable {
            client?.login();
        } else {
            client?.modulesManager.initIfRequired();
        }
    }
    
    public func getClient(account:BareJID) -> XMPPClient? {
        return clients[account];
    }
    
    private func registerModules(client:XMPPClient) {
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

    }
    
    private func registerEventHandlers(client:XMPPClient) {
        client.eventBus.register(self, events: SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, PresenceModule.BeforePresenceSendEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
        client.eventBus.register(dbChatHistoryStore, events: MessageModule.MessageReceivedEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE);
        for holder in eventHandlers {
            client.eventBus.register(holder.handler, events: holder.events);
        }
    }
    
    private func unregisterEventHandlers(client:XMPPClient) {
        client.eventBus.unregister(self, events: SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, PresenceModule.BeforePresenceSendEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE);
        client.eventBus.unregister(dbChatHistoryStore, events: MessageModule.MessageReceivedEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE);
        for holder in eventHandlers {
            client.eventBus.unregister(holder.handler, events: holder.events);
        }
    }
    
    public func handleEvent(event: Event) {
        switch event {
        case let e as SocketConnector.DisconnectedEvent:
            increaseBackgroundFetchTimeIfNeeded();
            networkAvailable = reachability.isConnectedToNetwork();
            if let jid = e.sessionObject.userBareJid {
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0)) {
                    self.updateXmppClientInstance(jid);
                }
            }
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            if e.features.contains(MessageCarbonsModule.MC_XMLNS) {
                if let messageCarbonsModule:MessageCarbonsModule = getClient(e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) {
                    messageCarbonsModule.enable();
                }
            }
        case let e as PresenceModule.BeforePresenceSendEvent:
            if UIApplication.sharedApplication().applicationState == .Active {
                e.presence.show = Presence.Show.online;
                e.presence.priority = 5;
            } else {
                e.presence.show = Presence.Show.away;
                e.presence.priority = 0;
            }
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            if applicationState == .inactive {
                if let mobileModeModule: MobileModeModule = getClient(e.sessionObject.userBareJid!)?.modulesManager.getModule(MobileModeModule.ID) {
                    mobileModeModule.enable();
                }
            }
            reconnectMucRooms(e.sessionObject.userBareJid!);
        default:
            log("received unsupported event", event);
        }
    }
    
    public func keepalive() {
        for client in clients.values {
            client.keepalive();
        }
    }
    
    private func applicationStateChanged() {
        sendAutoPresence();
        for client in clients.values {
            if client.state == .connected {
                if let mobileModeModule: MobileModeModule = client.modulesManager.getModule(MobileModeModule.ID) {
                    mobileModeModule.setState(applicationState == .inactive);
                }
            }
        }
    }
    
    private func sendAutoPresence() {
        for client in clients.values {
            if client.state == .connected {
                if let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) {
                    presenceModule.setPresence(.online, status: nil, priority: nil);
                }
            }
        }
    }
    
    public func registerEventHandler(handler:EventHandler, events:Event...) {
        log("registered event handler", handler, "for", events);
        eventHandlers.append(EventHandlerHolder(handler: handler, events: events));
        for client in clients.values {
            client.eventBus.register(handler, events: events);
        }
    }
    
    public func unregisterEventHandler(handler:EventHandler, events:Event...) {
        if let idx = eventHandlers.indexOf({ (holder) -> Bool in
            return holder.matches(handler, events: events);
        }) {
            log("removed event handler", handler, "for", events);
            eventHandlers.removeAtIndex(idx);
        } else {
            log("failed to remove event handler", handler, "for", events);
        }
        for client in clients.values {
            client.eventBus.unregister(handler, events: events);
        }
    }
    
    @objc public func accountConfigurationChanged(notification: NSNotification) {
        let accountName = notification.userInfo!["account"] as! String;
        let jid = BareJID(accountName);
        updateXmppClientInstance(jid);
    }
    
    @objc public func connectivityChanged(notification: NSNotification) {
        self.networkAvailable = notification.userInfo!["connected"] as! Bool;
    }
    
    public func preformFetch(completionHandler: (UIBackgroundFetchResult)->Void) {
        guard applicationState != .active else {
            print("skipping background fetch as application is active");
            completionHandler(.NewData);
            return;
        }
        guard networkAvailable == true else {
            print("skipping background fetch as network is not available");
            completionHandler(.Failed);
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
        backgroundFetchTimer = Timer(delayInSeconds: count > 0 ? fetchTimeLong : fetchTimeShort, repeats: false, callback: {
            self.backgroundFetchTimedOut();
        });
    }

    private func backgroundFetchTimedOut() {
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
        callback?(.NewData);
    }
    
    private func increaseBackgroundFetchTimeIfNeeded() {
        let timeout = backgroundFetchTimer?.timeout;
        if timeout != nil && timeout! < fetchTimeLong {
            let callback = backgroundFetchTimer!.callback;
            if callback != nil {
                backgroundFetchTimer?.cancel();
                backgroundFetchTimer = Timer(delayInSeconds: min(UIApplication.sharedApplication().backgroundTimeRemaining - 5, fetchTimeLong), repeats: false, callback: callback!);
            }
        }
    }
    
    private func connectClients(force: Bool = true) {
        for client in clients.values {
            client.login();
        }
    }
    
    private func disconnectClients(force:Bool = false) {
        for client in clients.values {
            client.disconnect(force);
        }
    }
    
    private func reconnectMucRooms(jid: BareJID) {
        if let client = getClient(jid) {
            guard client.state == .connected else {
                return;
            }
            if let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID) {
                for room in mucModule.roomsManager.getRooms() {
                    if room.state != .joined {
                        room.rejoin();
                    }
                }
            }
        }
    }
    
    private class EventHandlerHolder {
        let handler:EventHandler;
        let events:[Event];
        
        init(handler: EventHandler, events: [Event]) {
            self.handler = handler;
            self.events = events;
        }
        
        func matches(handler: EventHandler, events: [Event]) -> Bool {
            return self.handler === handler && self.events == events;
        }
    }
    
    public enum ApplicationState {
        case active
        case inactive
    }
}