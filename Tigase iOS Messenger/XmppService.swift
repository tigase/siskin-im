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


import Foundation
import TigaseSwift

public class XmppService: Logger, EventHandler {
    
    private let dbConnection:DBConnection;
    public var avatarManager:AvatarManager!;
    public let dbChatStore:DBChatStore;
    public let dbChatHistoryStore:DBChatHistoryStore;
    public let dbRosterStore:DBRosterStore;
    public let dbVCardsCache:DBVCardsCache;
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
    
    var firstClient:XMPPClient? {
        return clients.values.first;
    }
    
    init(dbConnection:DBConnection) {
        self.dbConnection = dbConnection;
        self.dbChatStore = DBChatStore(dbConnection: dbConnection);
        self.dbChatHistoryStore = DBChatHistoryStore(dbConnection: dbConnection);
        self.dbRosterStore = DBRosterStore(dbConnection: dbConnection);
        self.dbVCardsCache = DBVCardsCache(dbConnection: dbConnection);
        self.reachability = Reachability();
        self.networkAvailable = false;
        super.init();
        self.avatarManager = AvatarManager(xmppService: self);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(XmppService.accountConfigurationChanged), name:"accountConfigurationChanged", object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(XmppService.connectivityChanged), name: Reachability.CONNECTIVITY_CHANGED, object: nil);
        networkAvailable = reachability.isConnectedToNetwork();
    }
    
    public func updateJaxmppInstance() {
        for account in AccountManager.getAccounts() {
            updateJaxmppInstance(BareJID(account));
        }
    }
    
    public func updateJaxmppInstance(userJid:BareJID) {
        var client = clients[userJid];
        let password = AccountManager.getAccountPassword(userJid.stringValue);
        let config = AccountManager.getAccount(userJid.stringValue);
        
        if client == nil {
            if password == nil || config == nil || config?.active != true {
                return;
            }
            client = XMPPClient()
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
        }
    }
    
    public func getClient(account:BareJID) -> XMPPClient? {
        return clients[account];
    }
    
    private func registerModules(client:XMPPClient) {
        client.modulesManager.register(StreamManagementModule());
        client.modulesManager.register(AuthModule());
        client.modulesManager.register(StreamFeaturesModule());
        client.modulesManager.register(SaslModule());
        client.modulesManager.register(ResourceBinderModule());
        client.modulesManager.register(SessionEstablishmentModule());
        client.modulesManager.register(DiscoveryModule());
        client.modulesManager.register(SoftwareVersionModule());
        client.modulesManager.register(VCardModule());
        let rosterModule =  client.modulesManager.register(RosterModule());
        rosterModule.rosterStore = DBRosterStoreWrapper(sessionObject: client.sessionObject, store: dbRosterStore);
        client.modulesManager.register(PresenceModule());
        let messageModule = client.modulesManager.register(MessageModule());
        let chatManager = DefaultChatManager(context: client.context, chatStore: DBChatStoreWrapper(sessionObject: client.sessionObject, store: dbChatStore));
        messageModule.chatManager = chatManager;
        client.modulesManager.register(MessageCarbonsModule());
    }
    
    private func registerEventHandlers(client:XMPPClient) {
        client.eventBus.register(self, events: SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE);
        client.eventBus.register(dbChatHistoryStore, events: MessageModule.MessageReceivedEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE);
        for holder in eventHandlers {
            client.eventBus.register(holder.handler, events: holder.events);
        }
    }
    
    private func unregisterEventHandlers(client:XMPPClient) {
        client.eventBus.unregister(self, events: SocketConnector.DisconnectedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE);
        client.eventBus.unregister(dbChatHistoryStore, events: MessageModule.MessageReceivedEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE);
        for holder in eventHandlers {
            client.eventBus.unregister(holder.handler, events: holder.events);
        }
    }
    
    public func handleEvent(event: Event) {
        switch event {
        case let e as SocketConnector.DisconnectedEvent:
            if let jid = e.sessionObject.userBareJid {
                updateJaxmppInstance(jid);
            }
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            if e.features.contains(MessageCarbonsModule.MC_XMLNS) {
                if let messageCarbonsModule:MessageCarbonsModule = getClient(e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) {
                    messageCarbonsModule.enable();
                }
            }
        default:
            log("received unsupported event", event);
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
        updateJaxmppInstance(jid);
    }
    
    @objc public func connectivityChanged(notification: NSNotification) {
        self.networkAvailable = notification.userInfo!["connected"] as! Bool;
    }
    
    private func connectClients() {
        for client in clients.values {
            client.login();
        }
    }
    
    private func disconnectClients(force:Bool = false) {
        for client in clients.values {
            client.disconnect(force);
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
    
}