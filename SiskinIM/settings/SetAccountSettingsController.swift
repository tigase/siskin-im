//
// SetAccountSettingsController.swift
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
import Combine
import Martin

class SetAccountSettingsController: UITableViewController {

    var client: XMPPClient?;
    
    var sections: [Section] = [.accountName];
    
    @Published
    private var enableMAM: Bool = true;
    @Published
    private var initialSyncMAM: SyncPeriod = .month;
    
    var completionHandler: (()->Void)?;
    
    private var activityIndicator: UIActivityIndicatorView?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        activityIndicator = UIActivityIndicatorView(style: .large);
        activityIndicator?.translatesAutoresizingMaskIntoConstraints = false;
        activityIndicator?.hidesWhenStopped = true;
        if let view = activityIndicator {
            self.view.addSubview(view);
            NSLayoutConstraint.activate([
                view.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                view.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)
            ])
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let s = self.sections[section];
        switch s {
        case .accountName:
            return NSLocalizedString("For account", comment: "section label")
        case .mamEnable:
            return NSLocalizedString("Message synchronization", comment: "section label")
        case .mamSyncInitial:
            return NSLocalizedString("Initial synchronization", comment: "section label")
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        let s = self.sections[section];
        switch s {
        case .accountName:
            return "";
        case .mamEnable:
            return NSLocalizedString("Enabling message synchronization will enable message archiving on the server", comment: "option description")
        case .mamSyncInitial:
            return NSLocalizedString("Large value may increase inital synchronization time", comment: "option description");
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section];
        switch section {
        case .accountName:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AccountName", for: indexPath);
            cell.textLabel?.text = client?.userBareJid.description;
            return cell;
        case .mamEnable:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MAMEnable", for: indexPath) as! MAMEnable;
            cell.bind({ c in
                c.assign(from: $enableMAM.eraseToAnyPublisher());
                c.sink(to: \.enableMAM, on: self);
            })
            return cell;
        case .mamSyncInitial:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MAMInitialSync", for: indexPath) as! EnumTableViewCell;
            cell.bind({ c in
                c.assign(from: $initialSyncMAM.map({ $0.description }).eraseToAnyPublisher());
            })
            return cell;
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.section];
        switch section {
        case .mamSyncInitial:
            let controller = TablePickerViewController<SyncPeriod>(style: .grouped, message: NSLocalizedString("Select period of messages to be synchronized", comment: "selection description"), options: [.week,.twoWeeks,.month,.quarter,.year], value: initialSyncMAM);
            controller.sink(to: \.initialSyncMAM, on: self);
            self.navigationController?.pushViewController(controller, animated: true);
        default:
            break;
        }
    }
    
    @IBAction func skipClicked(_ sender: Any) {
        completionHandler?();
        NewFeaturesDetector.instance.showNext(fromController: true);
//        } else {
//            self.navigationController?.dismiss(animated: true, completion: nil);
//            (UIApplication.shared.delegate as? AppDelegate)?.showSetup(value: false);
//            self.completionHandler?();
//        }
    }
    
    @IBAction func doneClicked(_ sender: Any) {
        if let client = self.client {
            setInProgress(value: true);
            let group = DispatchGroup();
            let since = Date().addingTimeInterval(-1 * initialSyncMAM.timeInterval);
            DBChatHistorySyncStore.instance.addSyncPeriod(.init(account: client.userBareJid, from: since, after: nil, to: nil));
            MessageEventHandler.syncMessagePeriods(for: client);
            
            group.enter();
            var errors: [XMPPError] = [];
            client.module(.mam).retrieveSettings(completionHandler: { result in
                switch result {
                case .success(let settings):
                    var tmp = settings;
                    tmp.defaultValue = self.enableMAM ? .always : .never;
                    client.module(.mam).updateSettings(settings: tmp, completionHandler: { result in
                        switch result {
                        case .success(_):
                            break;
                        case .failure(let error):
                            errors.append(error);
                        }
                        group.leave();
                    })
                case .failure(let error):
                    errors.append(error);
                    group.leave();
                }
            })
            group.notify(queue: DispatchQueue.main, execute: {
//                guard errors.isEmpty else {
//                    return;
//                }
                self.setInProgress(value: false);
                self.completionHandler?();
                NewFeaturesDetector.instance.showNext(fromController: true);
            })
        } else {
            completionHandler?();
            NewFeaturesDetector.instance.showNext(fromController: true);
//            self.navigationController?.dismiss(animated: true, completion: nil);
//            (UIApplication.shared.delegate as? AppDelegate)?.showSetup(value: false);
//            self.completionHandler?();
        }
    }
    
    private func setInProgress(value: Bool) {
        if value {
            self.navigationItem.leftBarButtonItem?.isEnabled = false;
            self.navigationItem.rightBarButtonItem?.isEnabled = false;
            activityIndicator?.startAnimating();
        } else {
            self.navigationItem.leftBarButtonItem?.isEnabled = true;
            self.navigationItem.rightBarButtonItem?.isEnabled = true;
            activityIndicator?.stopAnimating();
        }
    }
        
    enum Section {
        case accountName
        case mamEnable
        case mamSyncInitial
    }
    
    enum SyncPeriod: CustomStringConvertible {
        case week
        case twoWeeks
        case month
        case quarter
        case year
        
        var description: String {
            switch self {
            case .week:
                return NSLocalizedString("Week", comment: "synchronization period value")
            case .twoWeeks:
                return NSLocalizedString("Two weeks", comment: "synchronization period value")
            case .month:
                return NSLocalizedString("Month", comment: "synchronization period value")
            case .quarter:
                return NSLocalizedString("Quarter", comment: "synchronization period value")
            case .year:
                return NSLocalizedString("Year", comment: "synchronization period value")
            }
        }
        
        var timeInterval: TimeInterval {
            let day: Double = 3600 * 24;
            switch self {
            case .week:
                return 7 * day;
            case .twoWeeks:
                return 14 * day;
            case .month:
                return 31 * day;
            case .quarter:
                return (366 / 4.0) * day;
            case .year:
                return 366 * day;
            }
        }
    }
}

class MAMEnable: SwitchTableViewCell {
        
}

class MAMInitialSync: EnumTableViewCell {
    
}
