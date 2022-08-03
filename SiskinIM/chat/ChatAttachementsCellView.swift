//
//  ChatAttachementsCellView.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 03/01/2020.
//  Copyright © 2020 Tigase, Inc. All rights reserved.
//

import UIKit
import MobileCoreServices
import Martin

class ChatAttachmentsCellView: UICollectionViewCell, UIDocumentInteractionControllerDelegate, UIContextMenuInteractionDelegate {

    @IBOutlet var imageField: UIImageView!

    private var id: Int {
        return item?.id ?? NSNotFound;
    };
    private var item: ConversationEntry?;
    
    func set(item: ConversationEntry) {
        self.item = item;
        
        self.addInteraction(UIContextMenuInteraction(delegate: self));
        
        if let fileUrl = DownloadStore.instance.url(for: "\(item.id)") {
            if let imageProvider = MetadataCache.instance.metadata(for: "\(item.id)")?.imageProvider {
                imageField.image = UIImage.icon(forFile: fileUrl, mimeType: nil);
                imageProvider.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil, completionHandler: { (data, error) in
                    guard let data = data, error == nil else {
                        return;
                    }
                    DispatchQueue.main.async {
                        guard self.id == item.id else {
                            return;
                        }
                        switch data {
                        case let image as UIImage:
                            self.imageField.image = image;
                        case let data as Data:
                            self.imageField.image = UIImage(data: data);
                        default:
                            break;
                        }
                    }
                });
            } else if let image = UIImage(contentsOfFile: fileUrl.path) {
                self.imageField.image = image;
            } else {
                self.imageField.image = UIImage.icon(forFile: fileUrl, mimeType: nil);
            }
        } else {
            if case .attachment(_, let appendix) = item.payload, let mimetype = appendix.mimetype, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue() as String? {
                imageField.image = UIImage.icon(forUTI: uti);
            } else {
                imageField.image = UIImage.icon(forUTI: "public.content")
            }
        }
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil, actionProvider: { suggestedActions in
            return self.prepareContextMenu();
        })
    }
    
    func prepareContextMenu() -> UIMenu {
        guard let item = self.item, case .attachment(let url, _) = item.payload else {
            return UIMenu(title: "");
        }
        
        if let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            let items = [
                UIAction(title: NSLocalizedString("Preview", comment: "context action"), image: UIImage(systemName: "eye.fill"), handler: { action in
                    self.open(url: localUrl, preview: true);
                }),
                UIAction(title: NSLocalizedString("Copy", comment: "context action"), image: UIImage(systemName: "doc.on.doc"), handler: { action in
                    UIPasteboard.general.strings = [url];
                    UIPasteboard.general.string = url;
                }),
                UIAction(title: NSLocalizedString("Share…", comment: "context action"), image: UIImage(systemName: "square.and.arrow.up"), handler: { action in
                    self.open(url: localUrl, preview: false);
                }),
                UIAction(title: NSLocalizedString("Delete", comment: "context action"), image: UIImage(systemName: "trash"), attributes: [.destructive], handler: { action in
                    DownloadStore.instance.deleteFile(for: "\(item.id)");
                    DBChatHistoryStore.instance.updateItem(for: item.conversation, id: item.id, updateAppendix: { appendix in
                        appendix.state = .removed;
                    })
                })
            ];
            return UIMenu(title: localUrl.lastPathComponent, image: nil, identifier: nil, options: [], children: items);
        } else {
            return UIMenu(title: "");
        }
    }
    
    var documentController: UIDocumentInteractionController?;
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        let viewController = ((UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.presentedViewController)!;
        return viewController;
    }
    
    func open(url: URL, preview: Bool) {
        let documentController = UIDocumentInteractionController(url: url);
        documentController.delegate = self;
        documentController.name = url.lastPathComponent;

        if preview && documentController.presentPreview(animated: true) {
            self.documentController = documentController;
        } else if documentController.presentOptionsMenu(from: self.superview?.convert(self.frame, to: self.superview?.superview) ?? CGRect.zero, in: self, animated: true) {
            self.documentController = documentController;
        }
    }

}
