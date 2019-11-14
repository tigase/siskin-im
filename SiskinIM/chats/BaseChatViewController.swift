//
// BaseChatViewController.swift
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
import UserNotifications
import TigaseSwift

class BaseChatViewController: UIViewController, UITextViewDelegate, UITableViewDelegate {

    @IBOutlet var tableView: UITableView!
    @IBOutlet fileprivate var messageField: UITextView!
    @IBOutlet var sendButton: UIButton!
    @IBOutlet var bottomPanel: UIView!;
    @IBOutlet var bottomView: UIView!
    @IBOutlet var placeholderView: UILabel!;
    
    var bottomPanelBottomConstraint: NSLayoutConstraint?;
    
    @IBInspectable var animateScrollToBottom: Bool = true;
    
    @IBOutlet var messageFieldTrailingConstraint: NSLayoutConstraint!
    @IBOutlet var sendButtonWidthConstraint: NSLayoutConstraint!
    
    var chat: DBChatProtocol!;
    
    var xmppService:XmppService!;
    
    var account:BareJID!;
    var jid:BareJID!;
    
    var messageText: String? {
        get {
            return messageField.text;
        }
        set {
            messageField.text = newValue;
            placeholderView?.isHidden = messageField.hasText;
        }
    }
        
    override func viewDidLoad() {
        xmppService = (UIApplication.shared.delegate as! AppDelegate).xmppService;
        super.viewDidLoad()
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .light
        };
        placeholderView?.text = "from \(account.stringValue)...";

        navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem;
        navigationItem.leftItemsSupplementBackButton = true;
        
        messageField.layer.masksToBounds = true;
        messageField.delegate = self;
        messageField.isScrollEnabled = false;
        if Settings.SendMessageOnReturn.getBool() {
            messageField.returnKeyType = .send;
            sendButtonWidthConstraint.isActive = false;
        } else {
            messageField.returnKeyType = .default;
            messageFieldTrailingConstraint.isActive = false;
        }
        
        tableView.rowHeight = UITableView.automaticDimension;
        tableView.estimatedRowHeight = 160.0;
        tableView.separatorStyle = .none;
        
        placeholderView?.isHidden = false;
        
//        bottomView.layer.borderColor = UIColor.lightGray.cgColor;
//        bottomView.layer.borderWidth = 0.5;
        bottomView.preservesSuperviewLayoutMargins = true;
        bottomPanelBottomConstraint = view.layoutMarginsGuide.bottomAnchor.constraint(equalTo: bottomPanel.bottomAnchor, constant: 0);
//        bottomViewBottomConstraint = view.bottomAnchor.constraint(equalTo: bottomView.bottomAnchor, constant: 0);
        bottomPanelBottomConstraint?.isActive = true;
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: Appearance.CHANGED, object: nil);
        updateAppearance();
    }

    override func didReceiveMemoryWarning() {
        
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
   
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(ChatViewController.keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil);
        
        if self.messageText?.isEmpty ?? true {
            self.xmppService.dbChatStore.getMessageDraft(account: account, jid: jid) { (text) in
                DispatchQueue.main.async {
                    self.messageText = text;
                }
            }
        }
        updateAppearance();
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);
        let accountStr = account.stringValue.lowercased();
        let jidStr = jid.stringValue.lowercased();
        self.tableView.backgroundColor = Appearance.current.systemBackground;
        UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
            var toRemove = [String]();
            for notification in notifications {
                if (notification.request.content.userInfo["account"] as? String)?.lowercased() == accountStr && (notification.request.content.userInfo["sender"] as? String)?.lowercased() == jidStr {
                    toRemove.append(notification.request.identifier);
                }
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: toRemove);
//            self.xmppService.dbChatHistoryStore.markAsRead(for: self.account, with: self.jid);
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
        if let account = self.account, let jid = self.jid {
            self.xmppService?.dbChatStore.updateMessageDraft(account: account, jid: jid, draft: messageText);
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self);
        super.viewDidDisappear(animated);
    }
    
    @objc func keyboardWillShow(_ notification: NSNotification) {
        keyboardAnimateHideShow(notification, hide: false);
    }
    
    @objc func keyboardWillHide(_ notification: NSNotification) {
        keyboardAnimateHideShow(notification, hide: true);
    }
    
    func keyboardAnimateHideShow(_ notification: NSNotification, hide: Bool) {
        if let userInfo = notification.userInfo {
            if let keyboardSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
                let oldHeight = bottomPanelBottomConstraint?.constant ?? CGFloat(0);
                let newHeight = hide ? 0 : (keyboardSize.height - self.view.layoutMargins.bottom);
                if (oldHeight - newHeight) != 0 {
                    let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as! TimeInterval;
                    let curve = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as! UInt;
                    bottomPanelBottomConstraint?.constant = newHeight;
                    UIView.animate(withDuration: duration, delay: 0.0, options: [UIView.AnimationOptions(rawValue: curve), UIView.AnimationOptions.layoutSubviews, UIView.AnimationOptions.beginFromCurrentState], animations: {
                        self.view.layoutIfNeeded();
                        }, completion: nil);
                }
            }
        }
    }

    func textViewDidChange(_ textView: UITextView) {
        placeholderView?.isHidden = textView.hasText;
    }
    
    
    @IBAction func tableViewClicked(_ sender: AnyObject) {
        messageField.resignFirstResponder();
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        cell.backgroundColor = Appearance.current.systemBackground;
    }
    
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            print("enter detected");
            if messageField.returnKeyType == .send {
                sendMessage();
                return false;
            }
        }
        return true;
    }
    
    func textViewDidEndEditing(_ textView: UITextView) {
        textView.resignFirstResponder();
    }
    
    func sendMessage() {
    }
    
    @objc func appearanceChanged(_ notification: Notification) {
        self.updateAppearance();
    }
    
    func updateAppearance() {
        self.messageField.keyboardAppearance = Appearance.current.isDark ? .dark : .default;
        self.messageField.backgroundColor = Appearance.current.systemBackground;
        self.messageField.textColor = Appearance.current.labelColor;
        self.messageField.layer.borderColor = Appearance.current.textFieldBorderColor.cgColor;
        self.messageField.layer.borderWidth = 0.5;
        self.messageField.layer.cornerRadius = 5.0;
        
        self.bottomView.tintColor = Appearance.current.bottomBarTintColor;
        self.bottomView.backgroundColor = Appearance.current.bottomBarBackgroundColor;
        
        self.view.tintColor = Appearance.current.tintColor;
        self.tableView.backgroundColor = Appearance.current.systemBackground;
        self.tableView.separatorColor = Appearance.current.secondarySystemBackground;
        
        if let navController = self.navigationController {
            navController.navigationBar.barStyle = Appearance.current.navigationBarStyle;
            navController.navigationBar.tintColor = Appearance.current.navigationBarTintColor;
            navController.navigationBar.barTintColor = Appearance.current.controlBackgroundColor;
            navController.navigationBar.setNeedsLayout();
            navController.navigationBar.layoutIfNeeded();
            navController.navigationBar.setNeedsDisplay();
        }
        DispatchQueue.main.async {
            self.tableView.reloadData();
        }
    }
}
