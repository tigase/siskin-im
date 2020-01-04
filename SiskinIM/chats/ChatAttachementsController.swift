//
//  ChatAttachementsController.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 03/01/2020.
//  Copyright © 2020 Tigase, Inc. All rights reserved.
//

import UIKit
import TigaseSwift

class ChatAttachmentsController: UICollectionViewController, UICollectionViewDelegateFlowLayout {

    private var items: [ChatAttachment] = [];
    
    var account: BareJID?;
    var jid: BareJID?;
    
    private var loaded: Bool = false;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(appearanceChanged), name: Appearance.CHANGED, object: nil);
        updateAppearance();
        if #available(iOS 13.0, *) {
        } else {
            self.view.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(gesture:))));
        }
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        self.updateAppearance();
        if let account = self.account, let jid = self.jid, !loaded {
            self.loaded = true;
            DBChatHistoryStore.instance.loadAttachments(for: account, with: jid, completionHandler: { attachments in
                DispatchQueue.main.async {
                    self.items = attachments.filter({ (attachment) -> Bool in
                        return DownloadStore.instance.url(for: "\(attachment.id)") != nil;
                    });
                    self.collectionView.reloadData();
                }
            });
        }
    }
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1;
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if items.isEmpty {
            if self.collectionView.backgroundView == nil {
                let label = UILabel(frame: CGRect(x: 0, y:0, width: self.view.bounds.size.width, height: self.view.bounds.size.height));
                label.text = "No attachments";
                label.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium);
                label.numberOfLines = 0;
                label.textAlignment = .center;
                label.sizeToFit();
                label.textColor = Appearance.current.secondaryLabelColor;
                self.collectionView.backgroundView = label;
            }
        } else {
            self.collectionView.backgroundView = nil;
        }
        return items.count;
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = self.collectionView.dequeueReusableCell(withReuseIdentifier: "AttachmentCellView", for: indexPath) as! ChatAttachmentsCellView;
        cell.set(item: items[indexPath.item]);
        return cell;
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (self.view.bounds.width - 2 * 2.0) / 3.0;
        return CGSize(width: width, height: width);
    }
    
    @objc func appearanceChanged(_ notification: Notification) {
        self.updateAppearance();
    }
    
    func updateAppearance() {
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = Appearance.current.isDark ? .dark : .light;
        };
        self.view.tintColor = Appearance.current.tintColor;
        
        self.collectionView.backgroundColor = Appearance.current.systemBackground;

        if let navController = self.navigationController {
            navController.navigationBar.barStyle = Appearance.current.navigationBarStyle;
            navController.navigationBar.tintColor = Appearance.current.navigationBarTintColor;
            navController.navigationBar.barTintColor = Appearance.current.controlBackgroundColor;
            navController.navigationBar.setNeedsLayout();
            navController.navigationBar.layoutIfNeeded();
            navController.navigationBar.setNeedsDisplay();
        }
    }

    @objc func messageUpdated(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let attachment = notification.object as? ChatAttachment, attachment.account == self.account, attachment.jid == self.jid else {
                return;
            }
            
            guard let idx = self.items.firstIndex(where: { (att) -> Bool in
                return att.id == attachment.id;
            }) else {
                return;
            }
            
            self.items.remove(at: idx);
            self.collectionView.deleteItems(at: [IndexPath(item: idx, section: 0)]);
        }
    }
    
    var documentController: UIDocumentInteractionController?;
    
    @objc func handleLongPress(gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .recognized else {
            return;
        }
        
        let p = gesture.location(in: self.collectionView);
        if let indexPath = self.collectionView.indexPathForItem(at: p) {
            let item = self.items[indexPath.row];
            if let url = DownloadStore.instance.url(for: "\(item.id)") {
                let documentController = UIDocumentInteractionController(url: url);
                //documentController.delegate = self;
                if documentController.presentOptionsMenu(from: CGRect.zero, in: self.collectionView, animated: true) {
                    self.documentController = documentController;
                }
            }
        }
    }

}
