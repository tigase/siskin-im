//
// AudioSession.swift
//
// Siskin IM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import AVFoundation

class AudioSesion {
    
    private(set) var outputMode: AudioOutputMode = .automatic;
    
    private let hasLoudSpeaker: Bool;
    private let preferSpeaker: Bool;
    
    init(preferSpeaker: Bool) {
        self.preferSpeaker = preferSpeaker;
        self.hasLoudSpeaker = UIDevice.current.model.lowercased().contains("iphone");
        NotificationCenter.default.addObserver(self, selector: #selector(audioRouteChanged), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        set(outputMode: .automatic)
    }
    
    func set(outputMode: AudioOutputMode) {
        self.outputMode = outputMode;
        try? self.updateCurrentAudioRoute();
    }
    
    enum Mode {
        case voiceChat
        case videoChat
    }
    
    enum AudioOutputMode: Equatable {
        case automatic
        case builtin
        case speaker
        case custom(AVAudioSessionPortDescription)
        
        var label: String {
            switch self {
            case .automatic:
                return NSLocalizedString("Automatic", comment: "audio output selection");
            case .builtin:
                return UIDevice.current.localizedModel;
            case .speaker:
                return NSLocalizedString("Speaker", comment: "audio output label");
            case .custom(let port):
                return port.portName;
            }
        }

        var icon: UIImage? {
            switch self {
            case .automatic:
                return nil;
            case .builtin:
                if UIDevice.current.model.lowercased().contains("iphone") {
                    return UIImage(systemName: "iphone");
                }
                if UIDevice.current.model.lowercased().contains("ipad") {
                    return UIImage(systemName: "ipad");
                }
                return nil;
            case .speaker:
                return UIImage(systemName: "speaker.wave.2");
            case .custom(let port):
                return port.portType.icon;
            }
        }

    }
    
    func availableAudioPorts() -> [AudioOutputMode] {
        var result: [AudioOutputMode] = [];
        
        let availableInputs = AVAudioSession.sharedInstance().availableInputs ?? [];
        
        for it in availableInputs {
            switch it.portType {
            case .builtInMic:
                result.append(.builtin);
                if hasLoudSpeaker {
                    result.append(.speaker);
                }
            default:
                result.append(.custom(it));
            }
        }
        
        return result;
    }
    
    @objc func audioRouteChanged(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, let reason = AVAudioSession.RouteChangeReason(rawValue: value) else {
            return;
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let that = self else {
                return;
            }
            
            let prevMode = that.outputMode;
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                that.outputMode = .automatic;
            default:
                break;
            }
            if prevMode != that.outputMode {
                try? that.updateCurrentAudioRoute();
            }
        }
    }
    
    func updateCurrentAudioRoute() throws {
        switch outputMode {
        case .builtin:
            try AVAudioSession.sharedInstance().setPreferredInput(nil);
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none);
        case .speaker:
            try AVAudioSession.sharedInstance().setPreferredInput(nil);
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker);
        case .custom(let port):
            try AVAudioSession.sharedInstance().setPreferredInput(port);
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(.none);
        case .automatic:
            try AVAudioSession.sharedInstance().setPreferredInput(nil);
            // we should use speaker by default if there is no headphone or car audio and there is a video being sent
            let useSpeaker = hasLoudSpeaker && preferSpeaker && (!isCarAudioPluggedIn()) && (!isHeadsetPluggedIn())
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(useSpeaker ? .speaker : .none);
        }
    }
    
    private func isHeadsetPluggedIn() -> Bool {
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { desc -> Bool in
            switch desc.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP:
                return true;
            default:
                return false;
            }
        });
    }

    private func isCarAudioPluggedIn() -> Bool {
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains(where: { desc -> Bool in
            switch desc.portType {
            case .carAudio:
                return true;
            default:
                return false;
            }
        });
    }
        
}


extension AVAudioSession.Port {
    
    var icon: UIImage? {
        switch self {
        case .builtInMic:
            return UIImage(systemName: "mic.fill")
        case .builtInSpeaker:
            return UIImage(systemName: "speaker.wave.2")
        case .headsetMic, .headphones:
            return UIImage(systemName: "headphones");
        case .bluetoothLE, .bluetoothHFP, .bluetoothA2DP:
            return UIImage(systemName: "wave.3.right");
        case .carAudio:
            return UIImage(systemName: "car.fill");
        default:
            return nil;
        }
    }
    
}
