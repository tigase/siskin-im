//
// ChartView.swift
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

class UsageChartView: UIStackView {
    
    private let barView = BarView();
    private let labelsView = UIStackView();
    
    var items: [Item] = [] {
        didSet {
            barView.items = items;
            for subview in labelsView.subviews {
                subview.removeFromSuperview();
            }
            
            let formatter = ByteCountFormatter();
            formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB];
            formatter.countStyle = .memory;
            for item in items {
                let row = UIStackView();
                row.isOpaque = false;
                row.axis = .horizontal;
                row.spacing = 10;
                row.distribution = .fill;
                row.alignment = .center;
                
                let colorView = ColorDotView();
                colorView.isOpaque = false;
                colorView.color = item.color;
                colorView.translatesAutoresizingMaskIntoConstraints = false;
                row.addArrangedSubview(colorView)
                NSLayoutConstraint.activate([
                    colorView.widthAnchor.constraint(equalTo: colorView.heightAnchor),
                    colorView.heightAnchor.constraint(equalToConstant: 10),
                ])

                let label = UILabel()
                label.font = UIFont.preferredFont(forTextStyle: .footnote);
                label.text = item.name;
                label.numberOfLines = 1;
                row.addArrangedSubview(label);
                
                let value = UILabel();
                value.font = UIFont.preferredFont(forTextStyle: .footnote);
                value.text = formatter.string(fromByteCount: Int64(item.value));
                value.textAlignment = .right;
                row.addArrangedSubview(value);
                labelsView.addArrangedSubview(row);
            }
        }
    }
    
    var maximumValue: Double = 100 {
        didSet {
            barView.totalValue = maximumValue;
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame);
        setup();
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
    
    func setup() {
        self.axis = .vertical;
        self.spacing = 10;
        
        barView.translatesAutoresizingMaskIntoConstraints = false;
        barView.setContentHuggingPriority(.defaultLow, for: .horizontal);
        barView.setContentHuggingPriority(.defaultLow, for: .vertical);
        barView.isOpaque = false;
        addArrangedSubview(barView);
        
        labelsView.axis = .vertical;
        labelsView.spacing = 4;
        labelsView.isOpaque = false;
        addArrangedSubview(labelsView);
        NSLayoutConstraint.activate([
            self.barView.heightAnchor.constraint(equalToConstant: 15)
        ]);
    }
            
    struct Item {
        let color: UIColor;
        let value: Double;
        let name: String;
    }
    
    class BarView: UIView {
    
        var items: [Item] = [];
        var totalValue: Double = 100;
        
        override func draw(_ rect: CGRect) {
            UIBezierPath(roundedRect: rect, cornerRadius: 5).addClip();
            UIColor.systemGray.setFill();
            UIBezierPath(rect: rect).fill();
            
            var x: CGFloat = 0;
            for item in items {
                let width = rect.width * CGFloat(item.value / totalValue);
                let path = UIBezierPath(rect: CGRect(x: x, y: 0, width: width, height: rect.height));
                item.color.setFill();
                path.fill();
                x = x + width;
            }
        }
        
    }
    
    class ColorDotView: UIView {
        
        var color: UIColor?;
        
        override func awakeFromNib() {
            super.awakeFromNib();
            isOpaque = false;
            setContentHuggingPriority(.defaultLow, for: .horizontal);
            setContentHuggingPriority(.defaultLow, for: .vertical);
        }
        
        override func draw(_ rect: CGRect) {
            let path = UIBezierPath(roundedRect: rect, cornerRadius: max(rect.height, rect.width));
            path.addClip();
            color?.setFill();
            path.fill();
        }
        
    }
}
