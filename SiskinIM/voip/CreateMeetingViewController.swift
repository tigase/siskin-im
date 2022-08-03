//
// CreateMeetingViewController.swift
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

class CreateMeetingViewController: MultiContactSelectionViewController {

    private let statusView = AccountStatusView();

    private var changeAccountButton: UIBarButtonItem!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    @Published
    fileprivate var client: XMPPClient?;
    
    @Published
    private var meetComponents: [MeetModule.MeetComponent] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        changeAccountButton = UIBarButtonItem(barButtonSystemItem: .organize, target: self, action: #selector(changeAccount(_:)));
        changeAccountButton.tintColor = UIColor(named: "tintColor")!;
        self.toolbarItems = [changeAccountButton, statusView];
        self.navigationController?.isToolbarHidden = false;
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Cancel", comment: "button label"), style: .plain, target: self, action: #selector(cancelTapped(_:)));
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Create", comment: "button label"), style: .done, target: self, action: #selector(createTapped(_:)));

        $selectedItems.combineLatest($meetComponents).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] items, components in
            self?.navigationItem.rightBarButtonItem?.isEnabled = (!items.isEmpty) && (!components.isEmpty);
        }).store(in: &cancellables);
        
        $client.receive(on: DispatchQueue.main).map({ $0?.userBareJid }).assign(to: \.account, on: statusView).store(in: &cancellables);
        
        $client.compactMap({ $0 }).sink(receiveValue: { [weak self] client in
            guard case .connected(_) =  client.state else {
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: NSLocalizedString("Default account is not connected. Please select a different account.", comment: "alert body"), preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                        self?.showChangeAccount();
                    }));
                    alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
                        self?.dismiss();
                    }))
                    self?.present(alert, animated: true, completion: nil);
                }
                return;
            }
            
            if let that = self {
                client.module(.meet).findMeetComponent(completionHandler: { result in
                    switch result {
                    case .success(let found):
                        DispatchQueue.main.async {
                            that.meetComponents = found;
                        }
                    case .failure(_):
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: NSLocalizedString("Server of selected account does not provide support for hosting meetings. Please select a different account.", comment: "alert body"), preferredStyle: .alert);
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                                that.showChangeAccount();
                            }));
                            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: { _ in
                                that.dismiss();
                            }))
                            that.present(alert, animated: true, completion: nil);
                        }
                        break;
                    }
                })
            }
        }).store(in: &cancellables);
        
        if let defAccount = AccountManager.defaultAccount, MeetEventHandler.instance.supportedAccounts.contains(defAccount) {
            client = XmppService.instance.getClient(for: defAccount);
        }        
    }
    
    @objc func changeAccount(_ sender: Any) {
        self.showChangeAccount();
    }
    
    private func showChangeAccount() {
        let selectAccountController = UIStoryboard(name: "VoIP", bundle: nil).instantiateViewController(withIdentifier: "SelectAccountController") as! SelectAccountController;
        selectAccountController.delegate = self;
        self.navigationController?.pushViewController(selectAccountController, animated: true);
    }
    
    @objc func createTapped(_ sender: Any) {
        guard let meetComponentJid = meetComponents.first?.jid, let client = self.client else {
            return;
        }
        
        let participants = self.selectedItems.map({ $0.jid });
        guard !participants.isEmpty else {
            return;
        }
        
        client.module(.meet).createMeet(at: meetComponentJid, media: [.audio,.video], participants: participants, completionHandler: { result in
            switch result {
            case .success(let meetJid):
                DispatchQueue.main.async {
                    self.dismiss();
                    DispatchQueue.main.async {
                        guard let manager = CallManager.instance else {
                            return;
                        }
                        manager.reportOutgoingCall(Meet(client: client, jid: meetJid.bareJid, sid: UUID().uuidString), completionHandler: { result in
                            switch result {
                            case .success(_):
                                for jid in participants {
                                    client.module(.meet).sendMessageInitiation(action: .propose(id: UUID().uuidString, meetJid: meetJid, media: [.audio,.video]), to: JID(jid));
                                }
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to initiate a call: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                                        self.dismiss();
                                    }))
                                    self.present(alert, animated: true, completion: nil);
                                }
                            }
                        });
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: NSLocalizedString("Error", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("It was not possible to create a meeting. Server returned an error: %@", comment: "alert body"), error.localizedDescription), preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "button label"), style: .default, handler: { _ in
                        self.dismiss();
                    }))
                    self.present(alert, animated: true, completion: nil);
                }
                break;
            }
        })
    }

    @objc func cancelTapped(_ sender: Any) {
        dismiss();
    }
    
    private func dismiss() {
        self.navigationController?.dismiss(animated: true, completion: nil);
    }
    
    class AccountStatusView: UIBarButtonItem {
        var account: BareJID? {
            didSet {
                let value = NSMutableAttributedString(string: "\(NSLocalizedString("Account", comment: "channel join status view label")): ", attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote), .foregroundColor: UIColor.secondaryLabel]);
                value.append(NSAttributedString(string: account?.stringValue ?? NSLocalizedString("None", comment: "channel join status view label"), attributes: [.font: UIFont.preferredFont(forTextStyle: .footnote), .foregroundColor: UIColor(named: "tintColor")!]));
                accountLabel.attributedText = value;
            }
        }

        private var accountLabel: UILabel!;
        
        override init() {
            super.init();
            setup();
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder);
            setup();
        }
        
        func setup() {
            let view = UIView();
            view.translatesAutoresizingMaskIntoConstraints = false;
            self.accountLabel = UILabel();
            accountLabel.isUserInteractionEnabled = false;
            accountLabel.font = UIFont.systemFont(ofSize: UIFont.systemFontSize);
            accountLabel.translatesAutoresizingMaskIntoConstraints = false;
            view.addSubview(accountLabel);

            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: accountLabel.topAnchor),
                view.leadingAnchor.constraint(equalTo: accountLabel.leadingAnchor),
                view.trailingAnchor.constraint(greaterThanOrEqualTo: accountLabel.trailingAnchor),
                accountLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            
            self.customView =  view;
            
            self.account = nil;
        }
    }

}

class SelectAccountController: UITableViewController, UIPickerViewDataSource, UIPickerViewDelegate {

    @IBOutlet var accountField: UITextField!;
    
    weak var delegate: CreateMeetingViewController?;

    private let accountPicker = UIPickerView();
    
    override func viewDidLoad() {
        super.viewDidLoad();
        tableView.dataSource = self;
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        let accountPicker = UIPickerView();
        accountPicker.dataSource = self;
        accountPicker.delegate = self;
        accountField.inputView = accountPicker;
        accountField.text = delegate?.client?.userBareJid.stringValue;
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if let account = BareJID(accountField!.text), let client = XmppService.instance.getClient(for: account) {
            delegate?.client = client;
        }
        super.viewWillDisappear(animated);
    }
     
//        override func numberOfSections(in tableView: UITableView) -> Int {
//            return 1;
//        }
//
//        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
//            return "Account"
//        }
//
//        override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
//            return "Select account which should be used for meeting creation."
//        }
    
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1;
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return AccountManager.getActiveAccounts().count;
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        return AccountManager.getActiveAccounts()[row].name.stringValue;
    }
    
    func  pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        self.accountField.text = self.pickerView(pickerView, titleForRow: row, forComponent: component);
    }

}
