//
// Reachability.swift
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
import SystemConfiguration

public class Reachability {
    
    public static let CONNECTIVITY_CHANGED = "messengerConnectivityChanged";
    
    private var defaultRouterReachability:SCNetworkReachability?;
    
    init() {
        var zeroAddress = sockaddr_in();
        zeroAddress.sin_len = UInt8(sizeofValue(zeroAddress));
        zeroAddress.sin_family = sa_family_t(AF_INET);
        defaultRouterReachability = withUnsafePointer(&zeroAddress) {
            SCNetworkReachabilityCreateWithAddress(nil, UnsafePointer($0));
        }
        var context = SCNetworkReachabilityContext();
        withUnsafeMutablePointer(&context) {
        SCNetworkReachabilitySetCallback(defaultRouterReachability!, { (reachability, flags, pointer) in
            let connected = Reachability.isConnectedToNetwork(flags);
            NSNotificationCenter.defaultCenter().postNotificationName(Reachability.CONNECTIVITY_CHANGED, object: nil, userInfo: ["connected": connected]);
            }, UnsafeMutablePointer($0))
        }
        SCNetworkReachabilityScheduleWithRunLoop(defaultRouterReachability!, NSRunLoop.currentRunLoop().getCFRunLoop(), NSDefaultRunLoopMode);
    }
    
    func isConnectedToNetwork() -> Bool {
        var flags = SCNetworkReachabilityFlags();
        if !SCNetworkReachabilityGetFlags(defaultRouterReachability!, &flags) {
            return false;
        }
        return Reachability.isConnectedToNetwork(flags);
    }
 
    static func isConnectedToNetwork(flags:SCNetworkReachabilityFlags) -> Bool {
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0;
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0;
        return isReachable && !needsConnection;
    }
}