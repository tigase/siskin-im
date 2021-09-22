//
// MediaSettingsVIewController.swift
//
// Siskin IM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import Shared

class MediaSettingsViewController: UITableViewController {
    
    let tree: [[SettingsEnum]] = [
        [SettingsEnum.sharingViaHttpUpload, SettingsEnum.maxImagePreviewSize],
        [SettingsEnum.imageUploadQuality, SettingsEnum.videoUploadQuality],
        [SettingsEnum.deviceMemoryUsage, SettingsEnum.clearDownloadStore, SettingsEnum.clearMetadataStore]
    ];
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return tree.count;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return tree[section].count;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Sharing", comment: "section label");
        case 1:
            return NSLocalizedString("Quality of uploaded media", comment: "section label");
        case 2:
            return String.localizedStringWithFormat(NSLocalizedString("%@ memory", comment: "section label, device memory"), UIDevice.current.localizedModel);
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return NSLocalizedString("Limits the size of the files sent to you which may be automatically downloaded", comment: "option description");
        case 1:
            return NSLocalizedString("Used image and video quality may impact storage and network usage", comment: "option description");
        case 2:
            return NSLocalizedString("Removal of cached attachments may lead to increased usage of network, if attachment may need to be redownloaded, or to lost files, if they are no longer available at the server.", comment: "option description");
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let setting = tree[indexPath.section][indexPath.row];
        switch setting {
        case .imageUploadQuality:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ImageQualityTableViewCell", for: indexPath) as! EnumTableViewCell;
            cell.bind({ cell in
                cell.assign(from: Settings.$imageQuality.map({ $0.label as String? }).eraseToAnyPublisher());
            })
            return cell;
        case .videoUploadQuality:
            let cell = tableView.dequeueReusableCell(withIdentifier: "VideoQualityTableViewCell", for: indexPath) as! EnumTableViewCell;
            cell.bind({ cell in
                cell.assign(from: Settings.$videoQuality.map({ $0.label as String? }).eraseToAnyPublisher());
            })
            return cell;
        case .sharingViaHttpUpload:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SharingViaHttpUploadTableViewCell", for: indexPath ) as! SwitchTableViewCell;
            cell.bind({ cell in
                cell.assign(from: Settings.$sharingViaHttpUpload);
            })
            cell.switchView.isOn = Settings.sharingViaHttpUpload;
            cell.valueChangedListener = {(switchView: UISwitch) in
                if switchView.isOn {
                    let alert = UIAlertController(title: nil, message: NSLocalizedString("When you share files using HTTP, they are uploaded to HTTP server with unique URL. Anyone who knows the unique URL to the file is able to download it.\nDo you wish to enable?", comment: "alert body"), preferredStyle: .alert);
                    alert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action) in
                        Settings.sharingViaHttpUpload = true;
                    }));
                    alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: { (action) in
                        switchView.isOn = false;
                    }));
                    self.present(alert, animated: true, completion: nil);
                } else {
                    Settings.sharingViaHttpUpload = false;
                }
            }
            return cell;
        case .maxImagePreviewSize:
            let cell = tableView.dequeueReusableCell(withIdentifier: "MaxImagePreviewSizeTableViewCell", for: indexPath) as! EnumTableViewCell;
            cell.bind({ cell in
                cell.assign(from: Settings.$fileDownloadSizeLimit.map({ value in
                    return value == Int.max ? NSLocalizedString("Unlimited", comment: "allowed size of file to download") : "\(value) MB";
                }).eraseToAnyPublisher());
            })
            cell.accessoryType = .disclosureIndicator;
            return cell;
        case .deviceMemoryUsage:
            let cell = tableView.dequeueReusableCell(withIdentifier: "DeviceMemoryUsageTableViewCell", for: indexPath);
            return cell;
        case .clearDownloadStore:
            return tableView.dequeueReusableCell(withIdentifier: "ClearDownloadStoreTableViewCell", for: indexPath);
        case .clearMetadataStore:
            return tableView.dequeueReusableCell(withIdentifier: "ClearMetadataStoreTableViewCell", for: indexPath);
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        let setting = tree[indexPath.section][indexPath.row];
        switch setting {
        case .maxImagePreviewSize:
            let controller = TablePickerViewController<Int>(style: .grouped, options: [0, 1, 2, 4, 8, 10, 15, 30, 50, Int.max], value: Settings.fileDownloadSizeLimit, labelFn: { value in
                return value == Int.max ? NSLocalizedString("Unlimited", comment: "allowed size of file to download") : "\(value) MB";
            });
            controller.sink(to: \.fileDownloadSizeLimit, on: Settings);
            self.navigationController?.pushViewController(controller, animated: true);
        case .imageUploadQuality:
            let controller = TablePickerViewController<ImageQuality>(style: .grouped, message: NSLocalizedString("Select quality of the image to use for sharing", comment: "selection description"), footer: NSLocalizedString("Original quality will share image in the format in which it is stored on your phone and it may not be supported by every device.", comment: "selection warning"), options: [.original, .highest, .high, .medium, .low], value: Settings.imageQuality, labelFn: { $0.label });
            controller.sink(to: \.imageQuality, on: Settings);
            self.navigationController?.pushViewController(controller, animated: true);
        case .videoUploadQuality:
            let controller = TablePickerViewController<VideoQuality>(style: .grouped, message: NSLocalizedString("Select quality of the video to use for sharing", comment: "selection description"), footer: NSLocalizedString("Original quality will share video in the format in which video is stored on your phone and it may not be supported by every device.", comment: "selection warning"), options: [.original, .high, .medium, .low], value: Settings.videoQuality, labelFn: { $0.label });
            controller.sink(to: \.videoQuality, on: Settings);
            self.navigationController?.pushViewController(controller, animated: true);
        case .clearDownloadStore:
            let formatter = ByteCountFormatter();
            formatter.allowedUnits = [.useKB,.useMB,.useGB,.useTB];
            formatter.countStyle = .memory;
            let alert = UIAlertController(title: NSLocalizedString("Download storage", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("We are using %@ of storage.", comment: "used space label"), formatter.string(fromByteCount: Int64(DownloadStore.instance.size))), preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Everything", comment: "option to remove all data from local storage"), style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    DownloadStore.instance.clear();
                }
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Older than 7 days", comment: "option to remove data older than 7 days"), style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    DownloadStore.instance.clear(olderThan: Date().addingTimeInterval(7*24*60*60.0*(-1.0)));
                }
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
            alert.popoverPresentationController?.sourceView = self.tableView;
            alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

            self.present(alert, animated: true, completion: nil);
            break;
        case .clearMetadataStore:
            let formatter = ByteCountFormatter();
            formatter.allowedUnits = [.useKB,.useMB,.useGB,.useTB];
            formatter.countStyle = .memory;
            let alert = UIAlertController(title: NSLocalizedString("Metadata storage", comment: "alert title"), message: String.localizedStringWithFormat(NSLocalizedString("We are using %@ of storage.", comment: "alert body"), formatter.string(fromByteCount: Int64(MetadataCache.instance.size))), preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: NSLocalizedString("Everything", comment: "option to remove all data from local storage"), style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    MetadataCache.instance.clear();
                }
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Older than 7 days", comment: "option to remove all data from local storage"), style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    MetadataCache.instance.clear(olderThan: Date().addingTimeInterval(7*24*60*60.0*(-1.0)));
                }
            }));
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: "button label"), style: .cancel, handler: nil));
            alert.popoverPresentationController?.sourceView = self.tableView;
            alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

            self.present(alert, animated: true, completion: nil);
        default:
            break;
        }
    }
    
    internal enum SettingsEnum: Int {
        case sharingViaHttpUpload
        case maxImagePreviewSize
        case clearDownloadStore
        case imageUploadQuality
        case videoUploadQuality
        case deviceMemoryUsage
        case clearMetadataStore
    }

}
