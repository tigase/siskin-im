//
// NotificationManager.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import Martin
import UserNotifications
import os
import Shared
import Combine
import TigaseLogging

public class NotificationManager: @unchecked Sendable {

    public static let instance: NotificationManager = NotificationManager();

    public let provider: NotificationManagerProvider!;

    private var queues: [NotificationQueueKey: NotificationQueue] = [:];
    
    private let queue = DispatchQueue(label: "NotificationManager");
    private var cancellables: Set<AnyCancellable> = [];
    private let logger = TigaseLogging.Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationManager");
    
    private init() {
        self.provider = MainNotificationManagerProvider();
        MessageEventHandler.eventsPublisher.receive(on: queue).sink(receiveValue: { [weak self] event in
            switch event {
            case .started(let account, let jid):
                self?.syncStarted(for: account, with: jid);
            case .finished(let account, let jid):
                self?.syncCompleted(for: account, with: jid);
            }
        }).store(in: &cancellables);
        DBChatHistoryStore.instance.markedAsRead.receive(on: queue).sink(receiveValue: { [weak self] marked in
            self?.markAsRead(on: marked.account, with: marked.jid, itemsIds: marked.messages.map({ $0.id }), before: marked.before);
        }).store(in: &cancellables);
        DBChatStore.instance.unreadMessageCountPublisher.delay(for: 0.1, scheduler: self.queue).throttle(for: 0.1, scheduler: self.queue, latest: true).sink(receiveValue: { [weak self] value in
            guard let that = self else {
                return;
            }
            Task {
                await that.updateApplicationIconBadgeNumber();
            }
        }).store(in: &cancellables);
        NotificationCenter.default.publisher(for: XmppService.AUTHENTICATION_ERROR).sink(receiveValue: { [weak self] notification in
            let account = notification.object as! BareJID;
            let error = notification.userInfo!["error"] as! SaslError;
            self?.authentication(error: error, on: account);
        }).store(in: &cancellables);
    }
    
    private func authentication(error: SaslError, on account: BareJID) {
        let content = UNMutableNotificationContent();
        content.body = String.localizedStringWithFormat(NSLocalizedString("Authentication for account %@ failed: %@", comment: "notification warning about authentication failure"), account.description, error.rawValue);
        content.userInfo = ["auth-error-type": error.rawValue, "account": account.description];
        content.categoryIdentifier = "ERROR";
        content.threadIdentifier = "account=" + account.description;
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil));
    }

    func newMessage(_ entry: ConversationEntry) {
        queue.async {
            guard entry.shouldNotify() else {
                return;
            }
            if let queue = self.queues[.init(account: entry.conversation.account, jid: entry.conversation.jid)] ?? self.queues[.init(account: entry.conversation.account, jid: nil)] {
                queue.add(message: entry);
            } else {
                self.notifyNewMessage(message: entry);
            }
        }
    }

    public func dismissAllNotifications(on account: BareJID, with jid: BareJID) {
        let threadId = "account=\(account.description)|sender=\(jid.description)";
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let toRemove = notifications.filter({ (notification) -> Bool in
                return notification.request.content.threadIdentifier == threadId;
            }).map({ (notification) -> String in
                return notification.request.identifier;
            });
                            
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
            Task {
                await self.updateApplicationIconBadgeNumber();
            }
        }
    }
    
    private func markAsRead(on account: BareJID, with jid: BareJID, itemsIds: [Int], before date: Date) {
        if let queue = self.queues[.init(account: account, jid: jid)] {
            queue.cancel(forIds: itemsIds);
        }
        if let queue = self.queues[.init(account: account, jid: nil)] {
            queue.cancel(forIds: itemsIds);
        }
//        let ids = itemsIds.map({ "message:\($0):new" });
//        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids);
        let threadId = "account=\(account.description)|sender=\(jid.description)";
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let toRemove = notifications.filter({ (notification) -> Bool in
                guard notification.request.content.threadIdentifier == threadId else {
                    return false;
                }
                guard let notificationDate = notification.request.content.userInfo["timestamp"] as? Date else {
                    return false;
                }
                return notificationDate < date;
            }).map({ (notification) -> String in
                return notification.request.identifier;
            });
                            
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
            Task {
                await self.updateApplicationIconBadgeNumber();
            }
        }
    }
        
    private func syncStarted(for account: BareJID, with jid: BareJID?) {
        queue.async {
            let key = NotificationQueueKey(account: account, jid: jid);
            if self.queues[key] == nil {
                self.queues[key] = NotificationQueue();
            }
        }
    }
        
    private func syncCompleted(for account: BareJID, with jid: BareJID?) {
        queue.async {
            if let messages = self.queues.removeValue(forKey: .init(account: account, jid: jid))?.unreadMessages {
                for message in messages {
                    self.notifyNewMessage(message: message);
                }
            }
        }
    }
    
    public func notifyNewMessage(account: BareJID, sender jid: BareJID?, nickname: String?, body: String, date: Date) {
        let id = UUID().uuidString;
        Task {
            let content = await NotificationsManagerHelper.prepareNewMessageNotification(content: UNMutableNotificationContent(), account: account, sender: jid, nickname: nickname, body: body, provider: provider);
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil));
            } catch {
                self.logger.error("message notification error \(error.localizedDescription)");
            }
        }
    }
    
    private func notifyNewMessage(message entry: ConversationEntry) {
        guard let conversation = entry.conversation as? Conversation else {
            return;
        }
                
        guard let body = entry.notificationContent else {
            return;
        }
        
        notifyNewMessage(account: conversation.account, sender: conversation.jid, nickname: entry.sender.nickname, body: body, date: entry.timestamp);
    }
        
    func updateApplicationIconBadgeNumber() async {
        let count = await provider.countBadge(withThreadId: nil);
        self.logger.debug("setting badge to: \(count)");
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = count;
        }
    }
    
    struct NotificationQueueKey: Hashable {
        let account: BareJID;
        let jid: BareJID?;
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(account);
            if let jid = jid {
                hasher.combine(jid);
            }
        }
    }

    class NotificationQueue {
        
        private(set) var unreadMessages: [ConversationEntry] = [];
 
        func add(message: ConversationEntry) {
            unreadMessages.append(message);
        }
        
        func cancel(forIds: [Int]) {
            let ids = Set(forIds);
            unreadMessages.removeAll(where: { ids.contains($0.id) });
        }
    }
}

extension ConversationEntry {
    
    func shouldNotify() -> Bool {
        guard case .incoming(let state) = self.state, state == .received else {
            return false;
        }
         
        guard let conversation = self.conversation as? Conversation else {
            return false;
        }
        
        switch payload {
        case .message(let message, _):
            switch conversation.notifications {
            case .none:
                return false;
            case .mention:
                if let nickname = (conversation as? Room)?.nickname ?? (conversation as? Channel)?.nickname {
                    if !message.contains(nickname) {
                        return false;
                    }
                } else {
                    return false;
                }
            default:
                break;
            }
        case .location(_):
            guard conversation.notifications == .always else {
                return false;
            }
        case .attachment(_, _):
            guard conversation.notifications == .always else {
                return false;
            }
        default:
            return false;
        }
        
        if conversation is Chat {
            guard Settings.notificationsFromUnknown || conversation.displayName != conversation.jid.description else {
                return false;
            }
        }
        
        return true;
    }
    
    var notificationContent: String? {
        switch self.payload {
        case .message(let message, _):
            return message;
        case .invitation(_, _):
            return "📨 \(NSLocalizedString("Invitation", comment: "invitation label for chats list"))"
        case .location(_):
            return "📍 \(NSLocalizedString("Location", comment: "attachemt label for conversations list"))";
        case .attachment(_, _):
            return "📎 \(NSLocalizedString("Attachment", comment: "attachemt label for conversations list"))";
        default:
            return nil;
        }
    }
}
