//
// AttachmentChatTableViewCell.swift
//
// Siskin IM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import MobileCoreServices
import LinkPresentation
import Martin
import AVFoundation

class AttachmentChatTableViewCell: BaseChatTableViewCell, UIContextMenuInteractionDelegate {
    
    @IBOutlet var customView: UIView!;
    
    override var backgroundColor: UIColor? {
        didSet {
            customView?.backgroundColor = backgroundColor;
        }
    }
    
    fileprivate var tapGestureRecognizer: UITapGestureRecognizer?;
    
    private var item: ConversationEntry?;
    
    private var linkView: UIView? {
        didSet {
            if let old = oldValue, let new = linkView {
                guard old != new else {
                    return;
                }
            }
            if let view = oldValue {
                view.removeFromSuperview();
            }
            if let view = linkView {
                self.customView.addSubview(view);
                if #available(iOS 13.0, *) {
                    view.addInteraction(UIContextMenuInteraction(delegate: self));
                }
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();
        tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tapGestureDidFire));
        tapGestureRecognizer?.cancelsTouchesInView = false;
        tapGestureRecognizer?.numberOfTapsRequired = 2;
        customView.addGestureRecognizer(tapGestureRecognizer!);
        
        customView.addInteraction(UIContextMenuInteraction(delegate: self));
    }
        
    func set(item: ConversationEntry, url: String, appendix: ChatAttachmentAppendix) {
        self.item = item;
        super.set(item: item);
        
        self.customView?.isOpaque = true;
//        self.customView?.backgroundColor = self.backgroundColor;
        
        guard case let .attachment(url, appendix) = item.payload else {
            return;
        }
        
        if !(appendix.mimetype?.starts(with: "audio/") ?? false), let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            documentController = UIDocumentInteractionController(url: localUrl);
            var metadata = MetadataCache.instance.metadata(for: "\(item.id)");
            let isNew = metadata == nil;
            if metadata == nil {
                metadata = LPLinkMetadata();
                metadata!.originalURL = localUrl;
            } else {
                metadata!.originalURL = nil;
                //metadata!.url = nil;
                //metadata!.title = "";
                //metadata!.originalURL = localUrl;
                metadata!.url = localUrl;
            }
                
            let linkView = /*(self.linkView as? LPLinkView) ??*/ LPLinkView(metadata: metadata!);
            linkView.setContentHuggingPriority(.defaultHigh, for: .vertical);
            linkView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            linkView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
            linkView.translatesAutoresizingMaskIntoConstraints = false;
            linkView.isUserInteractionEnabled = false;

            self.linkView = linkView;
            
            NSLayoutConstraint.activate([
                linkView.topAnchor.constraint(equalTo: self.customView.topAnchor, constant: 0),
                linkView.bottomAnchor.constraint(equalTo: self.customView.bottomAnchor, constant: 0),
                linkView.leadingAnchor.constraint(equalTo: self.customView.leadingAnchor, constant: 0),
                linkView.trailingAnchor.constraint(equalTo: self.customView.trailingAnchor, constant: 0),
                linkView.heightAnchor.constraint(lessThanOrEqualToConstant: 350)
            ]);
                
            if isNew {
                MetadataCache.instance.generateMetadata(for: localUrl, withId: "\(item.id)", completionHandler: { [weak self] meta1 in
                    DispatchQueue.main.async {
                        guard let that = self, meta1 != nil, that.item?.id == item.id else {
                            return;
                        }
                        NotificationCenter.default.post(name: ConversationLogController.REFRESH_CELL, object: that);
                    }
                })
            }
        } else {
            documentController = nil;

            let attachmentInfo = (self.linkView as? AttachmentInfoView) ?? AttachmentInfoView(frame: .zero);
            //attachmentInfo.backgroundColor = self.backgroundColor;
            //attachmentInfo.isOpaque = true;

            //attachmentInfo.cellView = self;
            self.linkView = attachmentInfo;
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: attachmentInfo.leadingAnchor),
                customView.trailingAnchor.constraint(greaterThanOrEqualTo: attachmentInfo.trailingAnchor),
                customView.topAnchor.constraint(equalTo: attachmentInfo.topAnchor),
                customView.bottomAnchor.constraint(equalTo: attachmentInfo.bottomAnchor)
            ])
            attachmentInfo.set(item: item, url: url, appendix: appendix);

            switch appendix.state {
            case .new:
                if DownloadStore.instance.url(for: "\(item.id)") == nil {
                    let sizeLimit = Settings.fileDownloadSizeLimit;
                    if sizeLimit > 0 {
                        if (DBRosterStore.instance.item(for: item.conversation.account, jid: JID(item.conversation.jid))?.subscription ?? .none).isFrom || (DBChatStore.instance.conversation(for: item.conversation.account, with: item.conversation.jid) as? Room != nil) {
                            _ = DownloadManager.instance.download(item: item, url: url, maxSize: sizeLimit >= Int.max ? Int64.max : Int64(sizeLimit * 1024 * 1024));
                            attachmentInfo.progress(show: true);
                            return;
                        }
                    }
                    attachmentInfo.progress(show: DownloadManager.instance.downloadInProgress(for: item));
                }
            default:
                attachmentInfo.progress(show: DownloadManager.instance.downloadInProgress(for: item));
            }
        }
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { suggestedActions -> UIMenu? in
            return self.prepareContextMenu();
        };
    }
    
    func prepareContextMenu() -> UIMenu {
        guard let item = self.item, case .attachment(let url, _) = item.payload else {
            return UIMenu(title: "");
        }
        
        if let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            let items = [
                UIAction(title: NSLocalizedString("Preview", comment: "attachment cell context action"), image: UIImage(systemName: "eye.fill"), handler: { action in
                    self.open(url: localUrl, preview: true);
                }),
                UIAction(title: NSLocalizedString("Copy", comment: "attachment cell context action"), image: UIImage(systemName: "doc.on.doc"), handler: { action in
                    UIPasteboard.general.strings = [url];
                    UIPasteboard.general.string = url;
                }),
                UIAction(title: NSLocalizedString("Share…", comment: "attachment cell context action"), image: UIImage(systemName: "square.and.arrow.up"), handler: { action in
                    self.open(url: localUrl, preview: false);
                }),
                UIAction(title: NSLocalizedString("Delete", comment: "attachment cell context action"), image: UIImage(systemName: "trash"), attributes: [.destructive], handler: { action in
                    DownloadStore.instance.deleteFile(for: "\(item.id)");
                    DBChatHistoryStore.instance.updateItem(for: item.conversation, id: item.id, updateAppendix: { appendix in
                        appendix.state = .removed;
                    })
                }),
                UIAction(title: NSLocalizedString("More…", comment: "attachment cell context action"), image: UIImage(systemName: "ellipsis"), handler: { action in
                    NotificationCenter.default.post(name: Notification.Name("tableViewCellShowEditToolbar"), object: self);
                })
            ];
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: items);
        } else {
            let items = [
                UIAction(title: NSLocalizedString("Copy", comment: "attachment cell context action"), image: UIImage(systemName: "doc.on.doc"), handler: { action in
                    UIPasteboard.general.strings = [url];
                    UIPasteboard.general.string = url;
                }),
                UIAction(title: NSLocalizedString("Download", comment: "attachment cell context action"), image: UIImage(systemName: "square.and.arrow.down"), handler: { action in
                    self.download(for: item);
                }),
                UIAction(title: NSLocalizedString("More…", comment: "attachment cell context action"), image: UIImage(systemName: "ellipsis"), handler: { action in
                    NotificationCenter.default.post(name: Notification.Name("tableViewCellShowEditToolbar"), object: self);
                })
            ];
            return UIMenu(title: "", image: nil, identifier: nil, options: [], children: items);
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse();
        (self.linkView as? AttachmentInfoView)?.prepareForReuse();
    }
        
    @objc func tapGestureDidFire(_ recognizer: UITapGestureRecognizer) {
        downloadOrOpen();
    }
    
    var documentController: UIDocumentInteractionController? {
        didSet {
            if let value = oldValue {
                for recognizer in value.gestureRecognizers {
                    self.removeGestureRecognizer(recognizer)
                }
            }
            if let value = documentController {
                value.delegate = self;
                for recognizer in value.gestureRecognizers {
                    self.addGestureRecognizer(recognizer)
                }
            }
        }
    }
    
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        let rootViewController = ((UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController)!;
        if let viewController = rootViewController.presentingViewController {
            return viewController;
        }
        return rootViewController;
    }
    
    func open(url: URL, preview: Bool) {
        let documentController = UIDocumentInteractionController(url: url);
        documentController.delegate = self;
        if preview && documentController.presentPreview(animated: true) {
            self.documentController = documentController;
        } else if documentController.presentOptionsMenu(from: self.superview?.convert(self.frame, to: self.superview?.superview) ?? CGRect.zero, in: self.self, animated: true) {
            self.documentController = documentController;
        }
    }
    
    func download(for item: ConversationEntry) {
        guard let item = self.item, case .attachment(let url, _) = item.payload else {
            return;
        }
        _ = DownloadManager.instance.download(item: item, url: url, maxSize: Int64.max);
        (self.linkView as? AttachmentInfoView)?.progress(show: true);
    }
    
    private func downloadOrOpen() {
        guard let item = self.item else {
            return;
        }
        if let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
//            let tmpUrl = FileManager.default.temporaryDirectory.appendingPathComponent(localUrl.lastPathComponent);
//            try? FileManager.default.copyItem(at: localUrl, to: tmpUrl);
            open(url: localUrl, preview: true);
        } else {
            let alert = UIAlertController(title: NSLocalizedString("Download", comment: "confirmation dialog title"), message: NSLocalizedString("File is not available locally. Should it be downloaded?", comment: "confirmation dialog body"), preferredStyle: .alert);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Yes", comment: "button label"), style: .default, handler: { (action) in
                self.download(for: item);
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("No", comment: "button label"), style: .cancel, handler: nil));
            if let controller = (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController {
                controller.present(alert, animated: true, completion: nil);
            }
        }
    }
        
    class AttachmentInfoView: UIView, AVAudioPlayerDelegate {
        
        let iconView: ImageAttachmentPreview;
        let filename: UILabel;
        let details: UILabel;
        let actionButton: UIButton;
        
        private var viewType: ViewType = .none {
            didSet {
                guard viewType != oldValue else {
                    return;
                }
                switch oldValue {
                case .none:
                    break;
                case .audioFile:
                    NSLayoutConstraint.deactivate(audioFileViewConstraints);
                case .file:
                    NSLayoutConstraint.deactivate(fileViewConstraints);
                case .imagePreview:
                    NSLayoutConstraint.deactivate(imagePreviewConstraints);
                }
                switch viewType {
                case .none:
                    break;
                case .audioFile:
                    NSLayoutConstraint.activate(audioFileViewConstraints);
                case .file:
                    NSLayoutConstraint.activate(fileViewConstraints);
                case .imagePreview:
                    NSLayoutConstraint.activate(imagePreviewConstraints);
                }
                iconView.contentMode = viewType == .imagePreview ? .scaleAspectFill : .scaleAspectFit;
                iconView.isImagePreview = viewType == .imagePreview;
            }
        }
        
        private var fileViewConstraints: [NSLayoutConstraint] = [];
        private var imagePreviewConstraints: [NSLayoutConstraint] = [];
        private var audioFileViewConstraints: [NSLayoutConstraint] = [];
        
        private static var labelFont: UIFont {
            let font = UIFont.preferredFont(forTextStyle: .headline);
            return font.withSize(font.pointSize - 2);
        }
        
        private static var detailsFont: UIFont {
            let font = UIFont.preferredFont(forTextStyle: .subheadline);
            return font.withSize(font.pointSize - 2);
        }
        
        private var fileUrl: URL?;

        override init(frame: CGRect) {
            iconView = ImageAttachmentPreview(frame: .zero);
            iconView.clipsToBounds = true
            iconView.image = UIImage(named: "defaultAvatar")!;
            iconView.translatesAutoresizingMaskIntoConstraints = false;
            iconView.setContentHuggingPriority(.defaultHigh, for: .vertical);
            iconView.setContentHuggingPriority(.defaultHigh, for: .horizontal);
            iconView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            iconView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);

            filename = UILabel(frame: .zero);
            filename.numberOfLines = 0
            filename.font = AttachmentInfoView.labelFont//.font = UIFont.systemFont(ofSize: UIFont.systemFontSize, weight: .semibold);
//            filename.adjustsFontForContentSizeCategory = true;
            filename.translatesAutoresizingMaskIntoConstraints = false;
            filename.setContentHuggingPriority(.defaultHigh, for: .horizontal);
            filename.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
            filename.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            
            details = UILabel(frame: .zero);
            details.font = AttachmentInfoView.detailsFont// UIFont.systemFont(ofSize: UIFont.systemFontSize - 2, weight: .regular);
//            details.adjustsFontForContentSizeCategory = true;
            details.textColor = UIColor.secondaryLabel;
            details.translatesAutoresizingMaskIntoConstraints = false;
            details.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            details.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
            details.numberOfLines = 0;

            actionButton = UIButton.systemButton(with: UIImage(systemName: "play.circle.fill")!, target: nil, action: nil);
            actionButton.translatesAutoresizingMaskIntoConstraints = false;
            actionButton.tintColor = UIColor(named: "tintColor");
            
            super.init(frame: frame);
            self.clipsToBounds = true
            self.translatesAutoresizingMaskIntoConstraints = false;
            self.isOpaque = false;
            
            addSubview(iconView);
            addSubview(filename);
            addSubview(details);
            addSubview(actionButton);
            
            fileViewConstraints = [
                iconView.heightAnchor.constraint(equalToConstant: 30),
                iconView.widthAnchor.constraint(equalTo: iconView.heightAnchor),
                
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
                iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                iconView.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor, constant: 8),
//                iconView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor, constant: -8),
                
                filename.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                filename.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                filename.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -10),
                
                details.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                details.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 4),
                details.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                // -- this is causing issue with progress indicatior!!
                details.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -10),
                details.heightAnchor.constraint(equalTo: filename.heightAnchor),
                
                actionButton.heightAnchor.constraint(equalToConstant: 0),
                actionButton.widthAnchor.constraint(equalToConstant: 0),
                actionButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0),
                actionButton.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0)
            ];
            
            audioFileViewConstraints = [
                iconView.heightAnchor.constraint(equalToConstant: 30),
                iconView.widthAnchor.constraint(equalTo: iconView.heightAnchor),
                
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
                iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                iconView.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor, constant: 8),
//                iconView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor, constant: -8),
                
                filename.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                filename.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                filename.trailingAnchor.constraint(lessThanOrEqualTo: self.actionButton.leadingAnchor, constant: -10),
                
                details.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                details.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 4),
                details.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                // -- this is causing issue with progress indicatior!!
                details.trailingAnchor.constraint(lessThanOrEqualTo: self.actionButton.leadingAnchor, constant: -10),
                
                actionButton.heightAnchor.constraint(equalToConstant: 30),
                actionButton.widthAnchor.constraint(equalTo: actionButton.heightAnchor),
                actionButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
                actionButton.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                actionButton.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor, constant: 8)
            ];
            
            imagePreviewConstraints = [
                iconView.widthAnchor.constraint(lessThanOrEqualToConstant: 350),
                iconView.heightAnchor.constraint(lessThanOrEqualToConstant: 350),
                iconView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor),
                iconView.heightAnchor.constraint(lessThanOrEqualTo: self.widthAnchor),
                
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                iconView.topAnchor.constraint(equalTo: self.topAnchor),
                iconView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                
                filename.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
                filename.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
                filename.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -16),
                
                details.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 16),
                details.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 4),
                details.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                details.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: -16),
                details.heightAnchor.constraint(equalTo: filename.heightAnchor),
                
                actionButton.heightAnchor.constraint(equalToConstant: 0),
                actionButton.widthAnchor.constraint(equalToConstant: 0),
                actionButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0),
                actionButton.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0)
            ];
            
            actionButton.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside);
        }
        
        required init?(coder: NSCoder) {
            return nil;
        }

        func prepareForReuse() {
            self.stopPlayingAudio();
        }
        
        override func draw(_ rect: CGRect) {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 10);
            path.addClip();
            UIColor.secondarySystemFill.setFill();
            path.fill();
            
            super.draw(rect);
        }
        
        static let timeFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter();
            formatter.unitsStyle = .abbreviated;
            formatter.zeroFormattingBehavior = .dropAll;
            formatter.allowedUnits = [.minute,.second]
            return formatter;
        }();
        
        func set(item: ConversationEntry, url: String, appendix: ChatAttachmentAppendix) {
            self.fileUrl = DownloadStore.instance.url(for: "\(item.id)");
            if let fileUrl = self.fileUrl {
                filename.text = fileUrl.lastPathComponent;
                let fileSize = fileSizeToString(try! FileManager.default.attributesOfItem(atPath: fileUrl.path)[.size] as? UInt64);
                if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileUrl.pathExtension as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                    details.text = "\(typeName) - \(fileSize)";
                    if UTTypeConformsTo(uti, kUTTypeImage) {
                        self.viewType = .imagePreview;
                        iconView.image = UIImage(contentsOfFile: fileUrl.path)!;
                    } else if UTTypeConformsTo(uti, kUTTypeAudio) {
                        self.viewType = .audioFile;
                        let asset = AVURLAsset(url: fileUrl);
                        asset.loadValuesAsynchronously(forKeys: ["duration"], completionHandler: {
                            DispatchQueue.main.async {
                                guard self.fileUrl == fileUrl else {
                                    return;
                                }
                                if asset.duration != .invalid && asset.duration != .zero {
                                    let length = CMTimeGetSeconds(asset.duration);
                                    if let lengthStr = AttachmentInfoView.timeFormatter.string(from: length) {
                                        self.details.text = "\(typeName) - \(fileSize) - \(lengthStr)";
                                    }
                                }
                            }
                        });
                        iconView.image = UIImage.icon(forUTI: uti as String) ?? UIImage.icon(forFile: fileUrl, mimeType: appendix.mimetype);
                    } else {
                        self.viewType = .file;
                        iconView.image = UIImage.icon(forFile: fileUrl, mimeType: appendix.mimetype);
                    }
                } else if let mimetype = appendix.mimetype, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                    details.text = "\(typeName) - \(fileSize)";
                    iconView.image = UIImage.icon(forUTI: uti as String) ?? UIImage.icon(forFile: fileUrl, mimeType: appendix.mimetype);
                    self.viewType = .file;
                } else {
                    details.text = String.localizedStringWithFormat(NSLocalizedString("File - %@", comment: "file size label"), fileSize);
                    iconView.image = UIImage.icon(forFile: fileUrl, mimeType: appendix.mimetype);
                    self.viewType = .file;
                }
            } else {
                let filename = appendix.filename ?? URL(string: url)?.lastPathComponent ?? "";
                if filename.isEmpty {
                    self.filename.text = NSLocalizedString("Unknown file", comment: "unknown file label");
                } else {
                    self.filename.text = filename;
                }
                if let size = appendix.filesize {
                    if let mimetype = appendix.mimetype, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                        let fileSize = size >= 0 ? fileSizeToString(UInt64(size)) : "";
                        details.text = "\(typeName) - \(fileSize)";
                        iconView.image = UIImage.icon(forUTI: uti as String);
                    } else {
                        details.text = String.localizedStringWithFormat(NSLocalizedString("File - %@", comment: "file size label"),fileSizeToString(UInt64(size)));
                        iconView.image = UIImage.icon(forUTI: "public.content");
                    }
                } else {
                    details.text = "--";
                    iconView.image = UIImage.icon(forUTI: "public.content");
                }
                self.viewType = .file;
            }
        }
        
        var progressView: UIActivityIndicatorView?;
        
        func progress(show: Bool) {
            guard show != (progressView != nil) else {
                return;
            }
            
            if show {
                let view = UIActivityIndicatorView(style: .medium);
                view.translatesAutoresizingMaskIntoConstraints = false;
                self.addSubview(view);
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(greaterThanOrEqualTo: filename.trailingAnchor, constant: 8),
                    view.leadingAnchor.constraint(greaterThanOrEqualTo: details.trailingAnchor, constant: 8),
                    view.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
                    view.bottomAnchor.constraint(equalTo: self.bottomAnchor),
                    view.topAnchor.constraint(lessThanOrEqualTo: self.topAnchor)
                ])
                self.progressView = view;
                view.startAnimating();
            } else if let view = progressView {
                view.stopAnimating();
                self.progressView = nil;
                view.removeFromSuperview();
            }
        }

        
        func fileSizeToString(_ sizeIn: UInt64?) -> String {
            guard let size = sizeIn else {
                return "";
            }
            let formatter = ByteCountFormatter();
            formatter.countStyle = .file;
            return formatter.string(fromByteCount: Int64(size));
        }
        
        enum ViewType {
            case none
            case file
            case imagePreview
            case audioFile
        }
        
        private var audioPlayer: AVAudioPlayer?;
        
        private func startPlayingAudio() {
            stopPlayingAudio();
            guard let fileUrl = self.fileUrl else {
                return;
            }
            do {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default);
                try? AVAudioSession.sharedInstance().setActive(true);
                audioPlayer = try AVAudioPlayer(contentsOf: fileUrl);
                audioPlayer?.delegate = self;
                audioPlayer?.volume = 1.0;
                audioPlayer?.play();
                self.actionButton.setImage(UIImage(systemName: "pause.circle.fill")!, for: .normal);
            } catch {
                self.stopPlayingAudio();
            }
        }
        
        private func stopPlayingAudio() {
            audioPlayer?.stop();
            audioPlayer = nil;
            self.actionButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal);
        }
        
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            audioPlayer?.stop();
            audioPlayer = nil;
            self.actionButton.setImage(UIImage(systemName: "play.circle.fill"), for: .normal);
        }
        
        @objc func actionTapped(_ sender: Any) {
            if audioPlayer == nil {
                self.startPlayingAudio();
            } else {
                self.stopPlayingAudio();
            }
        }
    }
}

class ImageAttachmentPreview: UIImageView {
    
    var isImagePreview: Bool = false {
        didSet {
            if isImagePreview != oldValue {
                if isImagePreview {
                    self.layer.cornerRadius = 10;
                    self.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner];
                } else {
                    self.layer.cornerRadius = 0;
                    self.layer.maskedCorners = [];
                }
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame);
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension FileManager {
    public func fileExtension(forUTI utiString: String) -> String? {
        guard
            let cfFileExtension = UTTypeCopyPreferredTagWithClass(utiString as CFString, kUTTagClassFilenameExtension)?.takeRetainedValue() else
        {
            return nil
        }

        return cfFileExtension as String
    }
}

extension UIImage {
    class func icon(forFile url: URL, mimeType: String?) -> UIImage? {
        let controller = UIDocumentInteractionController(url: url);
        if mimeType != nil, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimeType! as CFString, nil)?.takeRetainedValue() as String? {
            controller.uti = uti;
        }
        if controller.icons.count == 0 {
            controller.uti = "public.data";
        }
        let icons = controller.icons;
        return icons.last;
    }

    class func icon(forUTI utiString: String) -> UIImage? {
        let controller = UIDocumentInteractionController(url: URL(fileURLWithPath: "temp.file"));
        controller.uti = utiString;
        if controller.icons.count == 0 {
            controller.uti = "public.data";
        }
        let icons = controller.icons;
        return icons.last;
    }
    
}
