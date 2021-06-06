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

class MediaSettingsViewController: UITableViewController {
    
    let tree: [[SettingsEnum]] = [
        [SettingsEnum.sharingViaHttpUpload, SettingsEnum.maxImagePreviewSize],
        [SettingsEnum.imageUploadQuality, SettingsEnum.videoUploadQuality],
        [SettingsEnum.clearDownloadStore]
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
            return "";
        case 1:
            return "Quality of uploaded media";
        case 2:
            return "";
        default:
            return nil;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Limits the size of the files sent to you which may be automatically downloaded";
        case 1:
            return "Used image and video quality may impact storage and network usage"
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
                cell.assign(from: Settings.$imageQuality.map({ $0.rawValue.capitalized as String? }).eraseToAnyPublisher());
            })
            return cell;
        case .videoUploadQuality:
            let cell = tableView.dequeueReusableCell(withIdentifier: "VideoQualityTableViewCell", for: indexPath) as! EnumTableViewCell;
            cell.bind({ cell in
                cell.assign(from: Settings.$videoQuality.map({ $0.rawValue.capitalized as String? }).eraseToAnyPublisher());
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
                    let alert = UIAlertController(title: nil, message: "When you share files using HTTP, they are uploaded to HTTP server with unique URL. Anyone who knows the unique URL to the file is able to download it.\nDo you wish to enable?",preferredStyle: .alert);
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
                    return value == Int.max ? "Unlimited" : "\(value) MB";
                }).eraseToAnyPublisher());
            })
            cell.accessoryType = .disclosureIndicator;
            return cell;
        case .clearDownloadStore:
            return tableView.dequeueReusableCell(withIdentifier: "ClearDownloadStoreTableViewCell", for: indexPath);
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true);
        let setting = tree[indexPath.section][indexPath.row];
        switch setting {
        case .maxImagePreviewSize:
            let controller = TablePickerViewController<Int>(style: .grouped, options: [0, 1, 2, 4, 8, 10, 15, 30, 50, Int.max], value: Settings.fileDownloadSizeLimit, labelFn: { value in
                return value == Int.max ? "Unlimited" : "\(value) MB";
            });
            controller.sink(to: \.fileDownloadSizeLimit, on: Settings);
            self.navigationController?.pushViewController(controller, animated: true);
        case .clearDownloadStore:
            let alert = UIAlertController(title: "Download storage", message: "We are using \(DownloadStore.instance.size/(1024*1014)) MB of storage.", preferredStyle: .actionSheet);
            alert.addAction(UIAlertAction(title: "Flush", style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    DownloadStore.instance.clear();
                }
            }));
            alert.addAction(UIAlertAction(title: "Older than 7 days", style: .destructive, handler: {(action) in
                DispatchQueue.global(qos: .background).async {
                    DownloadStore.instance.clear(olderThan: Date().addingTimeInterval(7*24*60*60.0*(-1.0)));
                }
            }));
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil));
            alert.popoverPresentationController?.sourceView = self.tableView;
            alert.popoverPresentationController?.sourceRect = self.tableView.rectForRow(at: indexPath);

            self.present(alert, animated: true, completion: nil);
            break;
        case .imageUploadQuality:
            let controller = TablePickerViewController<ImageQuality>(style: .grouped, message: "Select quality of the image to use for sharing", footer: "Original quality will share image in the format in which it is stored on your phone and it may not be supported by every device.", options: [.original, .highest, .high, .medium, .low], value: Settings.imageQuality, labelFn: { $0.rawValue.capitalized });
            controller.sink(to: \.imageQuality, on: Settings);
            self.navigationController?.pushViewController(controller, animated: true);
        case .videoUploadQuality:
            let controller = TablePickerViewController<VideoQuality>(style: .grouped, message: "Select quality of the video to use for sharing", footer: "Original quality will share video in the format in which video is stored on your phone and it may not be supported by every device.", options: [.original, .high, .medium, .low], value: Settings.videoQuality, labelFn: { $0.rawValue.capitalized });
            controller.sink(to: \.videoQuality, on: Settings);
            self.navigationController?.pushViewController(controller, animated: true);
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
    }
    
    internal class ImageQualityItem: TablePickerViewItemsProtocol {
        
        public static func description(of value: ImageQuality) -> String {
            return value.rawValue.capitalized;
        }
        
        let description: String;
        let value: ImageQuality;
        
        init(value: ImageQuality) {
            self.value = value;
            self.description = ImageQualityItem.description(of: value);
        }
        
    }

    internal class VideoQualityItem: TablePickerViewItemsProtocol {
        
        public static func description(of value: VideoQuality) -> String {
            return value.rawValue.capitalized;
        }
        
        let description: String;
        let value: VideoQuality;
        
        init(value: VideoQuality) {
            self.value = value;
            self.description = VideoQualityItem.description(of: value);
        }
        
    }

}
