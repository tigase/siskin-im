//
// ChatViewInputBar.swift
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

class ChatViewInputBar: UIView, UITextViewDelegate, NSTextStorageDelegate {
    
    public let blurView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial);
        let view = UIVisualEffectView(effect: blurEffect);
        view.translatesAutoresizingMaskIntoConstraints = false;
        return view;
    }();
    
    public let bottomStackView: UIStackView = {
        let view = UIStackView();
        view.translatesAutoresizingMaskIntoConstraints = false;
        view.axis = .horizontal;
        view.alignment = .trailing;
        view.semanticContentAttribute = .forceRightToLeft;
        //        view.distribution = .fillEqually;
        view.spacing = 16;
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        return view;
    }();
    
    public let inputTextView: UITextView = {
        let layoutManager = MessageTextView.CustomLayoutManager();
        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude));
        textContainer.widthTracksTextView = true;
        let textStorage = NSTextStorage();
        textStorage.addLayoutManager(layoutManager);
        layoutManager.addTextContainer(textContainer);
        
        let view = UITextView(frame: .zero, textContainer: textContainer);
        view.isOpaque = false;
        view.backgroundColor = UIColor.clear;
        view.translatesAutoresizingMaskIntoConstraints = false;
        view.layer.masksToBounds = true;
//        view.delegate = self;
        view.isScrollEnabled = false;
        view.usesStandardTextScaling = false;
        view.font = Markdown.font(withTextStyle: .body, andTraits: []);
        if Settings.sendMessageOnReturn {
            view.returnKeyType = .send;
        } else {
            view.returnKeyType = .default;
        }
        view.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        return view;
    }()
    
    public let voiceRecordingView: VoiceRecordingView = {
        return VoiceRecordingView();
    }();
        
    public let placeholderLabel: UILabel = {
        let view = UILabel();
        view.numberOfLines = 0;
        view.textColor = UIColor.secondaryLabel;
        view.font = Markdown.font(withTextStyle: .body, andTraits: []);
        view.text = NSLocalizedString("Enter message…", comment: "placeholder");
        view.backgroundColor = .clear;
        view.translatesAutoresizingMaskIntoConstraints = false;
        return view;
    }();
    
    var placeholder: String? {
        get {
            return placeholderLabel.text;
        }
        set {
            placeholderLabel.text = newValue;
        }
    }
    
    var text: String? {
        get {
            return inputTextView.text;
        }
        set {
            inputTextView.text = newValue ?? "";
            placeholderLabel.isHidden = !inputTextView.text.isEmpty;
        }
    }
    
    weak var delegate: ChatViewInputBarDelegate?;
    
    convenience init() {
        self.init(frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 30)));
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame);
        self.setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
        
    func setup() {
        inputTextView.textStorage.delegate = self;
        translatesAutoresizingMaskIntoConstraints = false;
        isOpaque = false;
        setContentHuggingPriority(.defaultHigh, for: .horizontal);
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        addSubview(blurView);
        addSubview(inputTextView);
        addSubview(bottomStackView);
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: self.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            inputTextView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 6),
            inputTextView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -6),
            inputTextView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor),
            bottomStackView.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: 10),
            bottomStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -10),
            bottomStackView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: 0)
        ]);
        inputTextView.addSubview(placeholderLabel);
        NSLayoutConstraint.activate([
            inputTextView.leadingAnchor.constraint(equalTo: placeholderLabel.leadingAnchor, constant: -4),
            inputTextView.trailingAnchor.constraint(equalTo: placeholderLabel.trailingAnchor, constant: 4),
            inputTextView.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor),
            inputTextView.topAnchor.constraint(equalTo: placeholderLabel.topAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: placeholderLabel.bottomAnchor)
        ]);
        inputTextView.delegate = self;
    }
    
    @objc func startRecordingVoiceMessage(_ sender: Any) {
        UIView.animate(withDuration: 0.3, animations: {
            self.addSubview(self.voiceRecordingView);
            NSLayoutConstraint.activate([
                self.leadingAnchor.constraint(equalTo: self.voiceRecordingView.leadingAnchor),
                self.trailingAnchor.constraint(equalTo: self.voiceRecordingView.trailingAnchor),
                self.bottomAnchor.constraint(equalTo: self.voiceRecordingView.bottomAnchor),
                self.topAnchor.constraint(equalTo: self.voiceRecordingView.topAnchor)
            ])
        }, completion: { _ in
            self.voiceRecordingView.startRecording();
        })
    }
    
    override func layoutIfNeeded() {
        super.layoutIfNeeded();
        inputTextView.layoutIfNeeded();
    }
    
    override func resignFirstResponder() -> Bool {
        let val = super.resignFirstResponder();
        return val || inputTextView.resignFirstResponder();
    }
    
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = textView.hasText;
    }
        
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            if inputTextView.returnKeyType == .send {
                delegate?.sendMessage();
                return false;
            }
        }
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            delegate?.messageTextCleared();
        }
        return true;
    }
        
    func textViewDidEndEditing(_ textView: UITextView) {
        textView.resignFirstResponder();
    }

    func addBottomButton(_ button: UIButton) {
        bottomStackView.addArrangedSubview(button);
    }
    
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
        let fullRange = NSRange(0..<textStorage.length);
        textStorage.fixAttributes(in: fullRange);
        //textStorage.setAttributes([.font: self.font!], range: fullRange);
        textStorage.addAttributes([.foregroundColor: UIColor.label], range: fullRange);
        
        if Settings.enableMarkdownFormatting {
            Markdown.applyStyling(attributedString: textStorage, defTextStyle: .body, showEmoticons: false);
        }
    }
}



protocol ChatViewInputBarDelegate: AnyObject {
    
    func sendMessage();
    
    func messageTextCleared();
    
}


import AVFoundation
class VoiceRecordingView: UIView, AVAudioRecorderDelegate {
    
    public let blurView: UIVisualEffectView = {
        let blurEffect = UIBlurEffect(style: .systemMaterial);
        let blurView = UIVisualEffectView(effect: blurEffect);
        blurView.translatesAutoresizingMaskIntoConstraints = false;
        return blurView;
    }();
    
    public let stackView: UIStackView = {
        let stack = UIStackView();
        stack.axis = .horizontal;
        stack.alignment = .center;
        stack.distribution = .equalSpacing;
        stack.translatesAutoresizingMaskIntoConstraints = false;
        return stack;
    }();
    
    public let closeBtn: UIButton = {
        let closeBtn = UIButton.systemButton(with: UIImage(systemName: "xmark.circle.fill")!, target: self, action: #selector(hideVoiceRecordingView(_:)));
        closeBtn.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 10);
        closeBtn.tintColor = UIColor(named: "tintColor");
        return closeBtn;
    }();
    
    public let sendBtn: UIButton = {
        let sendBtn = UIButton.systemButton(with: UIImage(systemName: "paperplane.fill")!, target: self, action: #selector(sendTapped(_:)));
        sendBtn.tintColor = UIColor(named: "tintColor");
        sendBtn.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16);
        return sendBtn;
    }();
    
    public let actionBtn: UIButton = {
        let btn = UIButton.systemButton(with: UIImage(systemName: "stop.circle")!, target: self, action: #selector(actionTapped(_:)));
        btn.tintColor = UIColor.systemRed;
        btn.contentEdgeInsets = UIEdgeInsets(top: 16, left: 10, bottom: 16, right: 16);
        return btn;
    }();
    
    public let label: UILabel = {
        let label = UILabel();
        label.text = NSLocalizedString("Recording…", comment: "voice message state");
        label.setContentHuggingPriority(UILayoutPriority(200), for: .horizontal);
        return label;
    }();
    
    private var recordingStartTime: Date?;
    private var recordingEndedTime: Date?;
    private var timer: Timer?;
    
    weak var controller: BaseChatViewController?;
    
    private var action: Action = .recording {
        didSet {
            switch action {
            case .playing:
                self.startPlaying();
            case .stopped:
                if oldValue == .playing {
                    self.stopPlaying();
                } else if oldValue == .recording {
                    self.stopRecording();
                }
            default:
                break;
            }
            updateActionButton();
        }
    }
    
    private enum Action {
        case recording
        case stopped
        case playing
                
        var image: UIImage? {
            switch self {
            case .recording:
                return UIImage(systemName: "stop.circle");
            case .stopped:
                return UIImage(systemName: "play.circle");
            case .playing:
                return UIImage(systemName: "stop.circle");
            }
        }
        
        var tintColor: UIColor? {
            switch self {
            case .recording:
                return UIColor.systemRed;
            default:
                return UIColor(named: "tintColor");
            }
        }
    }
    
    convenience init() {
        self.init(frame: CGRect(origin: .zero, size: CGSize(width: 100, height: 30)));
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame);
        self.setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
    
    func setup() {
        self.translatesAutoresizingMaskIntoConstraints = false;
        self.addSubview(blurView);
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            blurView.topAnchor.constraint(equalTo: self.topAnchor),
            blurView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])

        self.addSubview(stackView);
        
        stackView.addArrangedSubview(closeBtn);
        stackView.addArrangedSubview(actionBtn);
        stackView.distribution = .fill;
        stackView.addArrangedSubview(label);
        stackView.addArrangedSubview(sendBtn);
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])
        
        updateActionButton();
    }
    
    @objc func hideVoiceRecordingView(_ sender: Any) {
        self.removeFromSuperview();
        stopRecording();
        reset();
    }
    
    func reset() {
        self.recordingEndedTime = nil;
        self.recordingStartTime = nil;
        self.fileUrl = nil;
        audioRecorder?.stop();
        audioRecorder = nil;
        timer?.invalidate();
        timer = nil;
        if let fileUrl = self.fileUrl {
            try? FileManager.default.removeItem(at: fileUrl);
        }
    }
    
    private var encoding: EncodingFormat = .MPEG4AAC;
    private var fileUrl: URL?;
    private var audioRecorder: AVAudioRecorder?;
    
    func startRecording() {
        AVAudioSession.sharedInstance().requestRecordPermission({ granted in
            DispatchQueue.main.async {
                guard granted else {
                    self.hideVoiceRecordingView(self);
                    return;
                }
                self.startRecordingInt()
            }
        })
    }
    
    private func startRecordingInt() {
        reset();
        
        fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)\(encoding.extensions)")
        
        recordingStartTime = Date();
        updateTime();
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { [weak self] _ in
            self?.updateTime();
        })
        
        let settings = encoding.settings;
         
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat);
            try AVAudioSession.sharedInstance().setActive(true);
            audioRecorder = try AVAudioRecorder(url: fileUrl!, settings: settings);
            audioRecorder?.delegate = self;
            audioRecorder?.record();
        } catch {
            reset();
            hideVoiceRecordingView(self);
        }
    }
    
    func stopRecording() {
        audioRecorder?.stop();
        audioRecorder = nil;
        recordingEndedTime = Date();
        timer?.invalidate();
        timer = nil;
        updateTime();
    }
    
    private var audioPlayer: AVAudioPlayer?;
    
    private enum EncodingFormat {
        case OPUS
        case MPEG4AAC
        
        var settings: [String: Any] {
            switch self {
            case .OPUS:
                return [AVFormatIDKey: kAudioFormatOpus, AVNumberOfChannelsKey: 1, AVSampleRateKey: 12000.0] as [String: Any];
            case .MPEG4AAC:
                return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1, AVSampleRateKey: 12000.0, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue] as [String: Any]
            }
        }
        
        var extensions: String {
            switch self {
            case .OPUS:
                return ".oga";
            case .MPEG4AAC:
                return ".m4a";
            }
        }
        
        var mimetype: String {
            switch self {
            case .OPUS:
                return "audio/ogg";
            case .MPEG4AAC:
                return "audio/mp4";
            }
        }
    }
    
    func startPlaying() {
        guard let fileUrl = self.fileUrl else {
            self.hideVoiceRecordingView(self);
            return;
        }
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: fileUrl)
            audioPlayer?.play();
        } catch {
            self.hideVoiceRecordingView(self);
        }
    }
    
    func stopPlaying() {
        audioPlayer?.stop();
        audioPlayer = nil;
    }
    
    static let timeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter();
        formatter.unitsStyle = .abbreviated;
        formatter.zeroFormattingBehavior = .dropAll;
        formatter.allowedUnits = [.minute,.second]
        return formatter;
    }();
    
    func updateTime() {
        guard let start = recordingStartTime else {
            return;
        }
        let diff = (recordingEndedTime ?? Date()).timeIntervalSince(start);
        switch self.action {
        case .recording:
            self.label.text = String.localizedStringWithFormat(NSLocalizedString("Recording… %@", comment: "voice message state"), VoiceRecordingView.timeFormatter.string(from: diff) ?? "");
        case .stopped:
            self.label.text = String.localizedStringWithFormat(NSLocalizedString("Recorded: %@", comment: "voice message state"), VoiceRecordingView.timeFormatter.string(from: diff) ?? "");
        case .playing:
            self.label.text = NSLocalizedString("Playing…", comment: "voice message state");
        }
    }
    
    func updateActionButton() {
        actionBtn.setImage(action.image, for: .normal);
        actionBtn.tintColor = action.tintColor;
        updateTime();
    }
    
    @objc func actionTapped(_ sender: Any) {
        switch action {
        case .recording, .playing:
            action = .stopped;
        case .stopped:
            action = .playing;
        }
    }
    
    @objc func sendTapped(_ sender: Any) {
        guard let url = self.fileUrl, let controller = self.controller else {
            return;
        }
        audioRecorder?.stop();
        self.fileUrl = nil;
        controller.share(filename: url.lastPathComponent, url: url, mimeType: encoding.mimetype, completionHandler: { result in
            switch result {
            case .success(let uploadedUrl, let filesize, let mimetype):
                var appendix = ChatAttachmentAppendix()
                appendix.filename = url.lastPathComponent;
                appendix.filesize = filesize;
                appendix.mimetype = mimetype;
                appendix.state = .downloaded;
                controller.sendAttachment(originalUrl: url, uploadedUrl: uploadedUrl.absoluteString, appendix: appendix, completionHandler: {
                });
            case .failure(let error):
                try? FileManager.default.removeItem(at: url);
                controller.showAlert(shareError: error);
            }
        })
        self.hideVoiceRecordingView(self);
    }
    
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {

    }
    
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        
    }
}
