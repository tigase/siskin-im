//
// ChatViewController.swift
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

class ChatViewController : UIViewController, UITableViewDataSource, UITextViewDelegate {
    
    @IBOutlet var tableView: UITableView!
    @IBOutlet var messageField: UITextView!
    @IBOutlet var sendButton: UIButton!
    @IBOutlet var bottomView: UIView!
    
    let PLACEHOLDER_TEXT = "Enter message...";
    
    var kbHeight: CGFloat!;
    
    var dbConnection:DBConnection {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.dbConnection;
    }
    
    var xmppService:XmppService! {
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate;
        return appDelegate.xmppService;
    }
    
    var account:BareJID!;
    var jid:JID!;
    
    var isFirstTime = true;
    
    private lazy var loadChatInfo:DBStatement! = try? self.dbConnection.prepareStatement("SELECT name FROM roster_items WHERE account = :account AND jid = :jid");
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.leftBarButtonItem = splitViewController?.displayModeButtonItem();
        navigationItem.leftItemsSupplementBackButton = true;
        navigationItem.title = jid.stringValue;
        let params:[String:Any?] = ["account" : account.stringValue, "jid" : jid.bareJid.stringValue];
        try! loadChatInfo.query(params) { (cursor) -> Void in
            self.navigationItem.title = cursor["name"];
        }
        
        messageField.delegate = self;
        
        tableView.rowHeight = UITableViewAutomaticDimension;
        tableView.estimatedRowHeight = 160.0;
        tableView.dataSource = self;
        tableView.separatorStyle = .None;

        applyPlaceHolderStyle(messageField);
    
        bottomView.layer.borderColor = UIColor.lightGrayColor().CGColor;
        bottomView.layer.borderWidth = 1.0;
        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false
        
        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
    }
    
    override func viewWillAppear(animated: Bool) {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.keyboardWillShow), name: UIKeyboardWillShowNotification, object: nil);
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.keyboardWillHide), name: UIKeyboardWillHideNotification, object: nil);
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatViewController.newMessage), name: "newMessage", object: nil);
        if isFirstTime {
            // scroll to bottom?
            let count = xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid);
            if count > 0 {
                let path = NSIndexPath(forRow: count - 1, inSection: 0);
                self.tableView.scrollToRowAtIndexPath(path, atScrollPosition: UITableViewScrollPosition.Bottom, animated: false);
                isFirstTime = false;
            }
        }
        
    }
    
    override func viewDidDisappear(animated: Bool) {
        NSNotificationCenter.defaultCenter().removeObserver(self);
        super.viewDidAppear(animated);
    }
    
    func keyboardWillShow(notification: NSNotification) {
        if let userInfo = notification.userInfo {
            if let keyboardSize = (userInfo[UIKeyboardFrameBeginUserInfoKey] as? NSValue)?.CGRectValue() {
                kbHeight = keyboardSize.height;
                self.animateTextField(true);
            }
        }
    }
    
    func keyboardWillHide(notification: NSNotification) {
        self.animateTextField(false);
    }
    
    func animateTextField(up:Bool) {
        let movement = up ? -kbHeight : kbHeight;
        if movement != nil {
            UIView.animateWithDuration(0.3) {
//                if (up) {
//                    self.view.frame = CGRectIntersection(self.view.frame, CGRectOffset(self.view.frame, 0, movement));
//                } else {
                let size = CGSize(width: self.view.frame.width, height: self.view.frame.height + movement);
//                }
                self.view.frame = CGRect(origin: self.view.frame.origin, size:size);
            }
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Table view data source
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1;
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid);
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        var cell:ChatTableViewCell? = nil;
        xmppService.dbChatHistoryStore.forEachMessage(account, jid: jid.bareJid, limit: 1, offset: indexPath.row) { (cursor) -> Void in
            let incoming = (cursor["state"]! % 2) == 0;
            let id = incoming ? "ChatTableViewCellIncoming" : "ChatTableViewCellOutgoing"
            cell = tableView.dequeueReusableCellWithIdentifier(id, forIndexPath: indexPath) as! ChatTableViewCell;
            cell!.avatarView.image = self.xmppService.avatarManager.getAvatar(self.jid.bareJid);
            cell!.messageTextView.text = cursor["data"];
            cell!.setTimestamp(cursor["timestamp"]!);
        }
        cell?.setNeedsUpdateConstraints();
        cell?.updateConstraintsIfNeeded();
        return cell!;
    }
    
    func newMessage(notification:NSNotification) {
        tableView.reloadData();
        let count = xmppService.dbChatHistoryStore.countMessages(account, jid: jid.bareJid);
        if count > 0 {
            let path = NSIndexPath(forRow: count - 1, inSection: 0);
            self.tableView.scrollToRowAtIndexPath(path, atScrollPosition: UITableViewScrollPosition.Bottom, animated: false);
            isFirstTime = false;
        }
    }
    
    @IBAction func sendClicked(sender: UIButton) {
        let text = messageField.text;
        guard !(text?.isEmpty != false) else {
            return;
        }
        
        let messageModule:MessageModule = xmppService.getClient(account).modulesManager.getModule(MessageModule.ID)!;
        let chat = messageModule.chatManager.getChat(jid, thread: nil);
        let msg = messageModule.sendMessage(chat!, body: text!);
        xmppService.dbChatHistoryStore.appendMessage(account, message: msg);
        messageField.text = nil;
    }
    
    func textViewShouldBeginEditing(textView: UITextView) -> Bool {
        if textView == messageField && textView.text == PLACEHOLDER_TEXT {
            dispatch_async(dispatch_get_main_queue()) {
                textView.selectedRange = NSMakeRange(0, 0);
            }
        }
        return true;
    }
   
    func applyPlaceHolderStyle(textView: UITextView) {
        textView.textColor = UIColor.lightGrayColor();
        textView.text = PLACEHOLDER_TEXT;
        dispatch_async(dispatch_get_main_queue()) {
            textView.selectedRange = NSMakeRange(0, 0);
        }
    }
    
    func textView(textView: UITextView, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool {
        let newLength = textView.text.utf16.count + text.utf16.count - range.length;
        if newLength > 0 {
            if textView == messageField && textView.text == PLACEHOLDER_TEXT {
                if text.utf16.count == 0 {
                    return false;
                }
                textView.textColor = UIColor.darkTextColor();
                textView.alpha = 1.0;
                textView.text = "";
            }
            return true;
        } else {
            applyPlaceHolderStyle(textView);
            return false;
        }
    }
    
}