//
// CameraPreviewView.swift
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
import AVFoundation
import WebRTC

class CameraPreviewView: UIView {
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self;
    }
    
    var viewAspectConstraint: NSLayoutConstraint?;
    
    var captureSession: AVCaptureSession? {
        didSet {
            DispatchQueue.main.async {
                let captureSession = self.captureSession;
                let previewLayer = self.previewLayer;
                RTCDispatcher.dispatchAsync(on: .typeCaptureSession) {
                    previewLayer.session = captureSession;
                    DispatchQueue.main.async {
                        self.updateOrientation();
                    }
                }
            }
        }
    }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        return self.layer as! AVCaptureVideoPreviewLayer;
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder);
        addOrientationObserver();
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame);
        addOrientationObserver();
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil);
    }
    
    override func layoutSubviews() {
        super.layoutSubviews();
        updateOrientation();
    }
    
    fileprivate func addOrientationObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIDevice.orientationDidChangeNotification, object: nil);
    }
    
    @objc func orientationChanged(_ notification: Notification) {
        updateOrientation();
    }
    
    fileprivate func updateOrientation() {
        if previewLayer.connection?.isVideoOrientationSupported ?? false {
            switch UIDevice.current.orientation {
            case .portraitUpsideDown:
                previewLayer.connection!.videoOrientation = .portraitUpsideDown;
            case .landscapeRight:
                previewLayer.connection!.videoOrientation = .landscapeLeft;
            case .landscapeLeft:
                previewLayer.connection!.videoOrientation = .landscapeRight;
            case .portrait:
                previewLayer.connection!.videoOrientation = .portrait;
            default:
                previewLayer.connection!.videoOrientation = .portrait;
            }
            updateAspect();
        }
    }
    
    func updateAspect() {
        if let oldConstraint = self.viewAspectConstraint {
            self.removeConstraint(oldConstraint);
            self.viewAspectConstraint = nil;
        }

        if let formatDescription = captureSession?.inputs.first?.ports.first?.formatDescription {
            let size = CMVideoFormatDescriptionGetDimensions(formatDescription);
            switch UIDevice.current.orientation {
            case .portraitUpsideDown, .portrait:
                self.viewAspectConstraint = self.widthAnchor.constraint(equalTo: self.heightAnchor, multiplier: CGFloat(size.height) / CGFloat(size.width));
            default:
                self.viewAspectConstraint = self.widthAnchor.constraint(equalTo: self.heightAnchor, multiplier: CGFloat(size.width) / CGFloat(size.height));
            }
            self.viewAspectConstraint?.isActive = true;
        } else {
            switch UIDevice.current.orientation {
            case .portraitUpsideDown, .portrait:
                self.viewAspectConstraint = self.widthAnchor.constraint(equalTo: self.heightAnchor, multiplier: CGFloat(16) / CGFloat(9));
            default:
                self.viewAspectConstraint = self.widthAnchor.constraint(equalTo: self.heightAnchor, multiplier: CGFloat(9) / CGFloat(16));
            }
            self.viewAspectConstraint?.isActive = true;
        }
    }
    
    func cameraChanged() {
        DispatchQueue.main.async {
            self.updateOrientation();
        }
    }
}
