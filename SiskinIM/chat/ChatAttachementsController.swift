//
//  ChatAttachementsController.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 03/01/2020.
//  Copyright © 2020 Tigase, Inc. All rights reserved.
//

import UIKit
import Martin
import Combine

class ChatAttachmentsController: UICollectionViewController, UICollectionViewDelegateFlowLayout {

    private var items: [ConversationEntry] = [];
    
    var conversation: Conversation!;
        
    private var loaded: Bool = false;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated);
        let conversation = self.conversation!;
        DBChatHistoryStore.instance.events.compactMap({ it -> ConversationEntry? in
            if case .updated(let item) = it {
                return item;
            }
            return nil;
        }).filter({ item in
            if case .attachment(_, _) = item.payload, item.conversation.account == conversation.account && item.conversation.jid == conversation.jid {
                return true;
            }
            return false;
        }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] value in
            if let idx = self?.items.firstIndex(where: { $0.id == value.id }) {
                self?.items[idx] = value;
                self?.collectionView.reloadItems(at: [IndexPath(row: idx, section: 0)]);
            }
        }).store(in: &cancellables);
        if !loaded {
            self.loaded = true;
            DBChatHistoryStore.instance.loadAttachments(for: conversation, completionHandler: { attachments in
                DispatchQueue.main.async {
                    self.items = attachments.filter({ (attachment) -> Bool in
                        return DownloadStore.instance.url(for: "\(attachment.id)") != nil;
                    });
                    self.collectionView.reloadData();
                }
            });
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated);
    }
    
    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1;
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if items.isEmpty {
            if self.collectionView.backgroundView == nil {
                let label = UILabel(frame: CGRect(x: 0, y:0, width: self.view.bounds.size.width, height: self.view.bounds.size.height));
                label.text = NSLocalizedString("No attachments", comment: "attachments view label");
                label.font = UIFont.systemFont(ofSize: UIFont.systemFontSize + 2, weight: .medium);
                label.numberOfLines = 0;
                label.textAlignment = .center;
                label.sizeToFit();
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

}
