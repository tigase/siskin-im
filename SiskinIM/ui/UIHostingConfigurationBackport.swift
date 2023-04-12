//
//  UIHostingConfigurationBackport.swift
//  Siskin IM
//
//  Created by Andrzej Wójcik on 20/03/2023.
//  Copyright © 2023 Tigase, Inc. All rights reserved.
//

import SwiftUI
import UIKit

final class HostingCell<Content: View>: UITableViewCell {
    let hostingController = UIHostingController<Content?>(rootView: nil)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false;
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        removeHostingControllerFromParent();
    }
    
//    override func sizeThatFits(_ size: CGSize) -> CGSize {
//        return hostingController.sizeThatFits(in: size)
//    }

//    override func layoutSubviews() {
//        super.layoutSubviews()
//        let newSize = self.sizeThatFits(bounds.size)
//        print("updating view size: \(newSize)")
//        hostingController.view.frame.size = newSize;
//    }

    public func set(rootView: Content, parentController: UIViewController) {
//        if var view = rootView as? ChatEntryView {
//            view.needResize = self.invalidateIntrinsicContentSize;
//            self.hostingController.rootView = view as! Content;
//        } else {
        self.hostingController.rootView = rootView
        self.hostingController.view.invalidateIntrinsicContentSize();
        
        let requiresControllerMove = hostingController.parent != parentController;
        if requiresControllerMove {
            removeHostingControllerFromParent();
            parentController.addChild(hostingController);
        }
//        }
        if !self.contentView.subviews.contains(hostingController.view) {
            self.contentView.addSubview(hostingController.view)
            NSLayoutConstraint.activate([
                hostingController.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                hostingController.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                hostingController.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                hostingController.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
        
        if requiresControllerMove {
            hostingController.didMove(toParent: parentController);
        }
    }
    
    func removeHostingControllerFromParent() {
        hostingController.willMove(toParent: nil)
        hostingController.view.removeFromSuperview();
        hostingController.removeFromParent();
    }
}

public struct UIHostingConfigurationBackport<Content, Background>: UIContentConfiguration where Content: View, Background: View {
  let content: Content
  let background: Background
  let margins: NSDirectionalEdgeInsets
  let minWidth: CGFloat?
  let minHeight: CGFloat?

  public init(@ViewBuilder content: () -> Content) where Background == EmptyView {
    self.content = content()
    background = .init()
    margins = .zero
    minWidth = nil
    minHeight = nil
  }

  init(content: Content, background: Background, margins: NSDirectionalEdgeInsets, minWidth: CGFloat?, minHeight: CGFloat?) {
    self.content = content
    self.background = background
    self.margins = margins
    self.minWidth = minWidth
    self.minHeight = minHeight
  }

  public func makeContentView() -> UIView & UIContentView {
    return UIHostingContentViewBackport<Content, Background>(configuration: self)
  }

  public func updated(for state: UIConfigurationState) -> UIHostingConfigurationBackport {
    return self
  }

  public func background<S>(_ style: S) -> UIHostingConfigurationBackport<Content, _UIHostingConfigurationBackgroundViewBackport<S>> where S: ShapeStyle {
    return UIHostingConfigurationBackport<Content, _UIHostingConfigurationBackgroundViewBackport<S>>(
      content: content,
      background: .init(style: style),
      margins: margins,
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  public func background<B>(@ViewBuilder content: () -> B) -> UIHostingConfigurationBackport<Content, B> where B: View {
    return UIHostingConfigurationBackport<Content, B>(
      content: self.content,
      background: content(),
      margins: margins,
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  public func margins(_ insets: EdgeInsets) -> UIHostingConfigurationBackport<Content, Background> {
    return UIHostingConfigurationBackport<Content, Background>(
      content: content,
      background: background,
      margins: .init(insets),
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  public func margins(_ edges: Edge.Set = .all, _ length: CGFloat) -> UIHostingConfigurationBackport<Content, Background> {
    return UIHostingConfigurationBackport<Content, Background>(
      content: content,
      background: background,
      margins: .init(
        top: edges.contains(.top) ? length : margins.top,
        leading: edges.contains(.leading) ? length : margins.leading,
        bottom: edges.contains(.bottom) ? length : margins.bottom,
        trailing: edges.contains(.trailing) ? length : margins.trailing
      ),
      minWidth: minWidth,
      minHeight: minHeight
    )
  }

  public func minSize(width: CGFloat? = nil, height: CGFloat? = nil) -> UIHostingConfigurationBackport<Content, Background> {
    return UIHostingConfigurationBackport<Content, Background>(
      content: content,
      background: background,
      margins: margins,
      minWidth: width,
      minHeight: height
    )
  }
}

class UIHostingControllerBackport<T: View>: UIHostingController<T> {
    
    var callback: (()->Void)?;
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews();
    }
    
}

final class UIHostingContentViewBackport<Content, Background>: UIView, UIContentView where Content: View, Background: View {
  private let hostingController: UIHostingControllerBackport<ZStack<TupleView<(Background, Content)>>?> = {
    let controller = UIHostingControllerBackport<ZStack<TupleView<(Background, Content)>>?>(rootView: nil)
    controller.view.backgroundColor = .clear
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    return controller
  }()

  var configuration: UIContentConfiguration {
    didSet {
      if let configuration = configuration as? UIHostingConfigurationBackport<Content, Background> {
        hostingController.rootView = ZStack {
          configuration.background
          configuration.content
        }
        directionalLayoutMargins = configuration.margins
      }
    }
  }

//  override var intrinsicContentSize: CGSize {
//    var intrinsicContentSize = super.intrinsicContentSize
//    if let configuration = configuration as? UIHostingConfigurationBackport<Content, Background> {
//      if let width = configuration.minWidth {
//        intrinsicContentSize.width = width//max(intrinsicContentSize.width, width)
//      }
//      if let height = configuration.minHeight {
//        intrinsicContentSize.height = height//max(intrinsicContentSize.height, height)
//      }
//    }
//    return intrinsicContentSize
//  }

  init(configuration: UIContentConfiguration) {
    self.configuration = configuration

    super.init(frame: .zero)
//      hostingController.callback = { [weak self] in
//          self?.invalidateIntrinsicContentSize();
//      }

    addSubview(hostingController.view)
    NSLayoutConstraint.activate([
      hostingController.view.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
      hostingController.view.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
      hostingController.view.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
      hostingController.view.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToSuperview() {
    if superview == nil {
      hostingController.willMove(toParent: nil)
      hostingController.removeFromParent()
    } else {
      parentViewController?.addChild(hostingController)
      hostingController.didMove(toParent: parentViewController)
    }
  }
}

public struct _UIHostingConfigurationBackgroundViewBackport<S>: View where S: ShapeStyle {
  let style: S

  public var body: some View {
    Rectangle().fill(style)
  }
}

private extension UIResponder {
  var parentViewController: UIViewController? {
    return next as? UIViewController ?? next?.parentViewController
  }
}

