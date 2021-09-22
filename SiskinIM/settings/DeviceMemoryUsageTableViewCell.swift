//
// DeviceMemoryUsageTableViewCell.swift
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

class DeviceMemoryUsageTableViewCell: UITableViewCell {
    
    let chartView = UsageChartView();
    
    var diskSpace = DiskSpace.current();
        
    override func awakeFromNib() {
        super.awakeFromNib();
        chartView.translatesAutoresizingMaskIntoConstraints = false;
        contentView.addSubview(chartView);
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: chartView.topAnchor, constant: -20),
            contentView.leadingAnchor.constraint(equalTo: chartView.leadingAnchor, constant: -20),
            contentView.trailingAnchor.constraint(equalTo: chartView.trailingAnchor, constant: 20),
            contentView.bottomAnchor.constraint(equalTo: chartView.bottomAnchor, constant: 20)
        ]);
        
        chartView.maximumValue = Double(diskSpace.total);
        
        let downloadsSize = DownloadStore.instance.size;
        let metadataSize = MetadataCache.instance.size;
        
        let usedByUs = downloadsSize + metadataSize;
        
        chartView.items = [
            .init(color: .systemYellow, value: Double(downloadsSize), name: NSLocalizedString("Downloads", comment: "memory usage label")),
            .init(color: .systemGreen, value: Double(metadataSize), name: NSLocalizedString("Link previews", comment: "memory usage label")),
            .init(color: .lightGray, value: Double(diskSpace.used - usedByUs), name: NSLocalizedString("Other apps", comment: "memory usage label")),
            .init(color: .systemGray, value: Double(diskSpace.free), name: NSLocalizedString("Free", comment: "memory usage label"))
        ]
    }
    
    struct DiskSpace {
        let total: Int;
        let free: Int;
        var used: Int {
            return total - free;
        }
        
        static func current() -> DiskSpace {
            do {
                let attrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory());
                let total = (attrs[.systemSize] as? NSNumber)?.intValue ?? 0;
                let free = (attrs[.systemFreeSize] as? NSNumber)?.intValue ?? 0;
                return .init(total: total, free: free);
            } catch {
                return DiskSpace(total: 0, free: 0);
            }
        }
    }
    
}

