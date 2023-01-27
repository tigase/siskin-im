//
// TestSelectorView.swift
//
// Siskin IM
// Copyright (C) 2023 "Tigase, Inc." <office@tigase.com>
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

import SwiftUI
import Shared

protocol SelectableItem: Identifiable, Hashable {
    
    associatedtype Value
    
    var label: String { get }
    var icon: UIImage? { get }
    var value: Value { get }
    
}

extension SelectableItem where Value == Self {
    
    var value: Self {
        return self;
    }
    
}

extension ImageQuality: SelectableItem {
    
    var icon: UIImage? {
        return nil;
    }

    var value: ImageQuality {
        return self;
    }
}

struct ItemSelectorView<ItemType: SelectableItem>: View {
        
    private let message: String;
    private let options: [ItemType];
    @State private var selected: ItemType?
    private let onChange: (ItemType.Value)->Void;
    
    init(message: String, options: [ItemType], selected: ItemType, onChange: @escaping (ItemType.Value)->Void) {
        self.message = message;
        self.options = options;
        self.onChange = onChange;
        self._selected = State(initialValue: selected);
    }
    
    var body: some View {
        List(selection: $selected, content: {
            Section(header: Text(message), footer: EmptyView(), content: {
                ForEach(options, id: \.id, content: { option in
                    ItemView(value: option)
                        .contentShape(Rectangle()).onTapGesture {
                            self.selected = option;
                            onChange(option.value)
                    }
                })
            })
        })
    }
    
    struct ItemView<ItemType: SelectableItem>: View {
        
        var value: ItemType;
        
        var body: some View {
            HStack {
                if let image = value.icon {
                    Image(uiImage: image).cornerRadius(10)
                }
                Text(value.label)
                Spacer()
            }
        }
    }
}

struct ItemSelectorView_Previews: PreviewProvider {
    static var previews: some View {
        //TestSelectorView<ImageQuality>(selected: .medium, options: [.highest, .high, .medium, .low])
        ItemSelectorView<SettingsStore.AppIcon>(message: "Select option", options: [.default, .simple], selected: .default, onChange: { newValue in
            
        })
    }
}
