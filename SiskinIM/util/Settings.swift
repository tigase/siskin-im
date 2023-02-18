//
// Settings.swift
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
import Martin
import Combine
import Shared
import SwiftUI

@propertyWrapper
struct Setting<T>: DynamicProperty {
    private let key: ReferenceWritableKeyPath<SettingsStore, T>;
    @ObservedObject private var settings = Settings;

    var wrappedValue: T {
        get {
            settings[keyPath: key];
        }
        set {
            settings[keyPath: key] = newValue;
        }
    }
    
    var projectedValue: Binding<T> {
        return settings.binding(keyPath: key);
    }
    
    init(_ key: ReferenceWritableKeyPath<SettingsStore, T>) {
        self.key = key;
    }
    
}

@propertyWrapper class UserDefaultsSetting<Value> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value,Never>;
        
    var projectedValue: AnyPublisher<Value,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, UserDefaultsSetting<Value>>
    ) -> Value {
        get {
            return object[keyPath: storageKeyPath].wrappedValue;
        }
        set {
            (object.objectWillChange as? ObservableObjectPublisher)?.send();
            object[keyPath: storageKeyPath].wrappedValue = newValue;
        }
    }
    
    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value = storage.value(forKey: key) as? Value ?? defaultValue;
        self.value = CurrentValueSubject<Value,Never>(value);
    }
}

@propertyWrapper class UserDefaultsRawSetting<Value: RawRepresentable> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value,Never>;
        
    var projectedValue: AnyPublisher<Value,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, UserDefaultsRawSetting<Value>>
    ) -> Value {
        get {
            return object[keyPath: storageKeyPath].wrappedValue;
        }
        set {
            (object.objectWillChange as? ObservableObjectPublisher)?.send();
            object[keyPath: storageKeyPath].wrappedValue = newValue;
        }
    }
    
    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value = storage.value(forKey: key) ?? defaultValue;
        self.value = CurrentValueSubject<Value,Never>(value);
    }
}

extension UserDefaultsSetting where Value: ExpressibleByNilLiteral {
    convenience init(key: String, storage: UserDefaults = .standard) {
        self.init(key: key, defaultValue: nil, storage: storage);
    }
}

extension UserDefaults {

    func value<T: RawRepresentable>(forKey key: String) -> T? {
        guard let value = value(forKey: key) as? T.RawValue else {
            return nil;
        }
        return T(rawValue: value);
    }
    
    func setValue<T: RawRepresentable>(_ value: T?, forKey key: String) {
        set(value?.rawValue, forKey: key);
    }
}

@propertyWrapper class UserDefaultsOptionalRawSetting<Value: RawRepresentable> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value?,Never>;
        
    var projectedValue: AnyPublisher<Value?,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value? {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value?>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, UserDefaultsOptionalRawSetting<Value>>
    ) -> Value? {
        get {
            return object[keyPath: storageKeyPath].wrappedValue;
        }
        set {
            (object.objectWillChange as? ObservableObjectPublisher)?.send();
            object[keyPath: storageKeyPath].wrappedValue = newValue;
        }
    }
    
    init(key: String, defaultValue: Value?, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value? = storage.value(forKey: key) ?? defaultValue;
        self.value = CurrentValueSubject<Value?,Never>(value);
    }
}

import SwiftUI

class SettingsStore: ObservableObject {
    @UserDefaultsSetting(key: "defaultAccount")
    var defaultAccount: String?;
    @UserDefaultsOptionalRawSetting(key: "StatusType", defaultValue: nil)
    var statusType: Presence.Show?;
    @UserDefaultsSetting(key: "StatusMessage")
    var statusMessage: String?;
    @UserDefaultsRawSetting(key: "RosterType", defaultValue: .flat)
    var rosterType: RosterType;
    @UserDefaultsRawSetting(key: "RosterItemsOrder", defaultValue: .alphabetical)
    var rosterItemsOrder: RosterSortingOrder;
    @UserDefaultsSetting(key: "RosterAvailableOnly", defaultValue: false)
    var rosterAvailableOnly: Bool;
    @UserDefaultsSetting(key: "RosterDisplayHiddenGroup", defaultValue: false)
    var rosterDisplayHiddenGroup: Bool;
    @UserDefaultsSetting(key: "AutoSubscribeOnAcceptedSubscriptionRequest", defaultValue: true)
    var autoSubscribeOnAcceptedSubscriptionRequest: Bool;
    @UserDefaultsSetting(key: "NotificationsFromUnknown", defaultValue: true)
    var notificationsFromUnknown: Bool
    @UserDefaultsSetting(key: "RecentsMessageLinesNo", defaultValue: 2)
    var recentsMessageLinesNo: Int;
    @UserDefaultsSetting(key: "SharingViaHttpUpload", defaultValue: false)
    var sharingViaHttpUpload: Bool;
    @UserDefaultsSetting(key: "fileDownloadSizeLimit", defaultValue: 4)
    var fileDownloadSizeLimit: Int;
    @UserDefaultsSetting(key: "confirmMessages", defaultValue: true)
    var confirmMessages: Bool;
    @UserDefaultsSetting(key: "SendMessageOnReturn", defaultValue: true)
    var sendMessageOnReturn: Bool;
    @UserDefaultsSetting(key: "CopyMessagesWithTimestamps", defaultValue: false)
    var copyMessagesWithTimestamps: Bool;
    @UserDefaultsSetting(key: "XmppPipelining", defaultValue: false)
    var xmppPipelining: Bool;
    
    @UserDefaultsSetting(key: "enableBookmarksSync", defaultValue: true)
    var enableBookmarksSync: Bool;
    @UserDefaultsRawSetting(key: "messageEncryption", defaultValue: ConversationEncryption.none)
    var messageEncryption: ConversationEncryption;
    @UserDefaultsSetting(key: "markdown", defaultValue: true)
    var enableMarkdownFormatting: Bool;
    @UserDefaultsSetting(key: "ShowEmoticons", defaultValue: false)
    var showEmoticons: Bool;
    
    @UserDefaultsSetting(key: "linkPreviews", defaultValue: true)
    var linkPreviews: Bool;
    @UserDefaultsRawSetting(key: "appearance", defaultValue: .auto)
    var appearance: Appearance
    @UserDefaultsSetting(key: "usePublicStunServers", defaultValue: true)
    var usePublicStunServers: Bool;
    
    @UserDefaultsRawSetting(key: "imageQuality", defaultValue: .medium)
    var imageQuality: ImageQuality
    @UserDefaultsRawSetting(key: "videoQuality", defaultValue: .medium)
    var videoQuality: VideoQuality

    @UserDefaultsSetting(key: "enablePush", defaultValue: nil)
    var enablePush: Bool?;
    
    func binding<T>(keyPath: ReferenceWritableKeyPath<SettingsStore,T>) -> Binding<T> {
        return .init(get: {
            return self[keyPath: keyPath];
        }, set: { value in
            self[keyPath: keyPath] = value;
        })
    }
    
    enum AppIcon: String, SelectableItem {
        case `default` = "AppIcon"
        case `simple` = "AppIcon-Simple"
        
        var label: String {
            switch self {
            case .default:
                return NSLocalizedString("Default", comment: "App icon")
            case .simple:
                return NSLocalizedString("Simple", comment: "App icon")
            }
        }
        
        var icon: UIImage? {
            return UIImage(named: self.rawValue);
        }
        
        var id: AppIcon {
            return self;
        }
        
    }
    
    @Published var appIcon: AppIcon;
    
    public static let sharedDefaults = UserDefaults(suiteName: "group.TigaseMessenger.Share")!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    fileprivate init() {
        appIcon = AppIcon(rawValue: UIApplication.shared.alternateIconName ?? "") ?? .default;
        $sharingViaHttpUpload.sink(receiveValue: { value in
            SettingsStore.sharedDefaults.setValue(value, forKey: "SharingViaHttpUpload");
        }).store(in: &cancellables);
        $imageQuality.sink(receiveValue: { value in
            SettingsStore.sharedDefaults.setValue(value.rawValue, forKey: "imageQuality");
        }).store(in: &cancellables);
        $videoQuality.sink(receiveValue: { value in
            SettingsStore.sharedDefaults.setValue(value.rawValue, forKey: "videoQuality");
        }).store(in: &cancellables);
    }
    
    public static func initialize() {
        UserDefaults.standard.removeObject(forKey: "DeleteChatHistoryOnClose");
        UserDefaults.standard.removeObject(forKey: "enableMessageCarbons");
        UserDefaults.standard.removeObject(forKey: "DeviceToken");
        UserDefaults.standard.removeObject(forKey: "RecentsOrder");
        UserDefaults.standard.removeObject(forKey: "AppearanceTheme");
        
        if UserDefaults.standard.value(forKey: "confirmMessages") == nil {
            if let value = UserDefaults.standard.value(forKey: "MessageDeliveryReceiptsEnabled") as? Bool {
                UserDefaults.standard.setValue(value, forKey: "confirmMessages");
                UserDefaults.standard.removeObject(forKey: "MessageDeliveryReceiptsEnabled");
            }
        }
        
        DispatchQueue.global(qos: .background).async {
            let removeOlder = Date().addingTimeInterval(7 * 24 * 60 * 60 * (-1.0));
            for (k,v) in SettingsStore.sharedDefaults.dictionaryRepresentation() {
                if k.starts(with: "upload-") {
                    let hash = k.replacingOccurrences(of: "upload-", with: "");
                    if let timestamp = (v as? [String: Any])?["timestamp"] as? Date {
                        if timestamp < removeOlder {
                            SettingsStore.sharedDefaults.removeObject(forKey: k);
                            let localUploadDirUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("upload", isDirectory: true).appendingPathComponent(hash, isDirectory: false);
                            if FileManager.default.fileExists(atPath: localUploadDirUrl.path) {
                                try? FileManager.default.removeItem(at: localUploadDirUrl);
                            }
                        }
                    } else {
                        SettingsStore.sharedDefaults.removeObject(forKey: k);
                        let localUploadDirUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.siskinim.shared")!.appendingPathComponent("upload", isDirectory: true).appendingPathComponent(hash, isDirectory: false);
                        if FileManager.default.fileExists(atPath: localUploadDirUrl.path) {
                            try? FileManager.default.removeItem(at: localUploadDirUrl);
                        }
                    }
                }
            }
        }
        
        let suffixesToRemove = ["MessageSyncAutomatic", "MessageSyncPeriod", "MessageSyncTime"];
        
        let keysToRemove = UserDefaults.standard.dictionaryRepresentation().keys.filter({ key in
            for suffix in suffixesToRemove {
                if suffix.hasSuffix(".\(suffix)") {
                    return true;
                }
            }
            return false;
        });
        
        for key in keysToRemove {
            UserDefaults.standard.removeObject(forKey: key);
        }
    }
}

let Settings: SettingsStore = {
    SettingsStore.initialize();
    return SettingsStore();
}();

enum Appearance: String, CustomStringConvertible, SelectableItem {
    var label: String {
        return description;
    }
    
    var icon: UIImage? {
        return nil;
    }
    
    var id: Appearance {
        return self;
    }
    
    var value: Appearance {
        return self;
    }
    
    case auto
    case light
    case dark
    
    var description: String {
        switch self {
        case .auto:
            return NSLocalizedString("Auto", comment: "appearance type")
        case .light:
            return NSLocalizedString("Light", comment: "appearance type")
        case .dark:
            return NSLocalizedString("Dark", comment: "appearance type")
        }
    }
    
    var uiInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .auto:
            return .unspecified;
        case .light:
            return .light;
        case .dark:
            return .dark;
        }
    }
}
