//
// LinkPreviewChatTableViewCell.swift
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
import LinkPresentation

class LinkPreviewChatTableViewCell: BaseChatTableViewCell {
    
    private var url: URL?;
    
    var linkView: LPLinkView? {
        didSet {
            if let value = oldValue {
                value.metadata = LPLinkMetadata();
                value.removeFromSuperview();
            }
            if let value = linkView {
                self.contentView.addSubview(value);
                NSLayoutConstraint.activate([
                    value.topAnchor.constraint(equalTo: self.contentView.topAnchor, constant: 2),
                    value.bottomAnchor.constraint(equalTo: self.contentView.bottomAnchor, constant: -4),
                    value.leadingAnchor.constraint(equalTo: self.contentView.leadingAnchor, constant: 44),
                    value.trailingAnchor.constraint(lessThanOrEqualTo: self.contentView.trailingAnchor, constant: -22)
                ]);
            }
        }
    }
    
    override func prepareForReuse() {
        self.url = nil;
        self.linkView?.metadata = LPLinkMetadata();
        super.prepareForReuse();
    }
        
    func set(item: ConversationEntry, url inUrl: String) {
        super.set(item: item);

        self.contentView.setContentCompressionResistancePriority(.required, for: .vertical);
        self.contentView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        
        let url = URL(string: inUrl)!;
        self.url = url;
        
        guard let metadata = MetadataCache.instance.metadata(for: "\(item.id)") else {
            setup(linkView: LPLinkView(metadata: createMetadata(url: url)));
            
            MetadataCache.instance.generateMetadata(for: url, withId: "\(item.id)", completionHandler: { [weak self] meta in
                guard meta != nil else {
                    return;
                }
                DispatchQueue.main.async {
                    guard let that = self, that.url == url else {
                        return;
                    }

                    NotificationCenter.default.post(name: ConversationLogController.REFRESH_CELL, object: that);
                }
            })
            
            return;
        }
        
        setup(linkView: LPLinkView(metadata: metadata));
    }
    
    private func createMetadata(url: URL) -> LPLinkMetadata {
        let metadata = LPLinkMetadata();
        metadata.originalURL = url;
        return metadata;
    }
    
    private func setup(linkView: LPLinkView) {
        linkView.setContentCompressionResistancePriority(.required, for: .vertical);
        linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        linkView.translatesAutoresizingMaskIntoConstraints = false;
        self.linkView = linkView;
    }
}
