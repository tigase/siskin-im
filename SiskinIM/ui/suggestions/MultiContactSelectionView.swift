//
// MultiContactSelectionView.swift
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
import Combine
import Martin

class MultiContactSelectionViewController: UITableViewController, UISearchControllerDelegate, MultiContactSearchControllerDelegate {
    
    @Published
    private(set) var selectedItems: [Item] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        tableView.rowHeight = UITableView.automaticDimension;
        tableView.estimatedRowHeight = UITableView.automaticDimension;
        tableView.register(SelectedItemCellView.self, forCellReuseIdentifier: "selectedItem");

        let searchResult = SearchResultController();
        searchResult.delegate = self;
        navigationItem.title = NSLocalizedString("Select contacts", comment: "title for multiple contact selection")
        navigationItem.searchController = UISearchController(searchResultsController: searchResult);
        navigationItem.searchController?.searchResultsUpdater = searchResult;
        navigationItem.searchController?.delegate = self;
        navigationItem.searchController?.searchBar.placeholder = NSLocalizedString("Search to add…", comment: "placeholder")
        navigationItem.searchController?.automaticallyShowsSearchResultsController = false;
        navigationItem.searchController?.showsSearchResultsController = true;
        navigationItem.searchController?.hidesNavigationBarDuringPresentation = false;

        navigationItem.hidesSearchBarWhenScrolling = false;
        navigationItem.searchController?.searchBar.searchBarStyle = .prominent;
        navigationItem.searchController?.isActive = true;
        definesPresentationContext = false;
        navigationItem.searchController?.searchBar.sizeToFit();
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return selectedItems.count;
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "selectedItem", for: indexPath) as! SelectedItemCellView;
        let item = selectedItems[indexPath.row];
        cell.contact = ContactManager.instance.contact(for: .init(account: item.account, jid: item.jid, type: .buddy));
        return cell;
    }
        
    func selected(item: Item) {
        var items = self.selectedItems;
        items.append(item);
        self.selectedItems = items.sorted();
        tableView.reloadData();
        navigationItem.searchController?.searchBar.searchTextField.text = nil;
        navigationItem.searchController?.isActive = false;
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            selectedItems.remove(at: indexPath.row);
            tableView.deleteRows(at: [indexPath], with: .automatic);
        }
    }
    
    class SearchResultController: UITableViewController, UISearchResultsUpdating {
        
        private let dispatcher = QueueDispatcher(label: "searchResultDispatcher");
        private var items: [Item] = [];
        private var cancellables: Set<AnyCancellable> = [];
        
        @Published
        private var queryString: String = "";
        
        weak var delegate: MultiContactSearchControllerDelegate?;
        
        override func viewDidLoad() {
            super.viewDidLoad();
            tableView.register(SelectedItemCellView.self, forCellReuseIdentifier: "selectedItem");
            DBRosterStore.instance.$items.combineLatest(Settings.$rosterDisplayHiddenGroup, $queryString).throttle(for: 0.1, scheduler: dispatcher.queue, latest: true).map({ items, displayHidden, query -> [RosterItem] in
                let notHidden = (displayHidden ? items : items.filter({ !$0.groups.contains("Hidden") }));
                return Array(query.isEmpty ? notHidden : notHidden.filter({ $0.name?.lowercased().contains(query) ?? false || $0.jid.stringValue.lowercased().contains(query)}));
            }).sink(receiveValue: { [weak self] items in
                self?.updateItems(items: items);
            }).store(in: &cancellables);
        }
        
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated);
            if let rows = tableView.indexPathsForVisibleRows {
                self.tableView.reloadRows(at: rows, with: .automatic);
            }
        }
        
        override func numberOfSections(in tableView: UITableView) -> Int {
            return 1;
        }
        
        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return items.count;
        }
        
        func updateItems(items: [RosterItem]) {
            let oldItems = self.items;
            let newItems: [Item] = items.compactMap({ item in
                guard let account = item.context?.userBareJid else {
                    return nil;
                }
                guard !item.annotations.contains(where: { $0.type == "mix" }) else {
                    return nil;
                }
                return Item(account: account, jid: item.jid.bareJid, displayName: item.name ?? item.jid.stringValue);
            }).sorted();

            let diff = newItems.calculateChanges(from: oldItems);
            
            DispatchQueue.main.sync {
                self.items = newItems;
                self.tableView.beginUpdates();
                self.tableView.deleteRows(at: diff.removed.map({ IndexPath(row: $0, section: 0) }), with: .fade);
                self.tableView.insertRows(at: diff.inserted.map({ IndexPath(row: $0, section: 0) }), with: .fade);
                self.tableView.endUpdates();
            }

        }
        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "selectedItem", for: indexPath) as! SelectedItemCellView;
            let item = items[indexPath.row];
            cell.accessoryType = (self.delegate?.selectedItems.contains(item) ?? false) ? .checkmark : .none;
            cell.contact = ContactManager.instance.contact(for: .init(account: item.account, jid: item.jid, type: .buddy));
            return cell;
        }

        
        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            delegate?.selected(item: items[indexPath.row]);
        }
        
        func updateSearchResults(for searchController: UISearchController) {
            self.queryString = searchController.searchBar.text?.lowercased() ?? "";
        }
    }
    
    struct Item: Hashable, Comparable {
        static func < (lhs: MultiContactSelectionViewController.Item, rhs: MultiContactSelectionViewController.Item) -> Bool {
            return lhs.displayName.lowercased() < rhs.displayName.lowercased();
        }
        
        let account: BareJID;
        let jid: BareJID;
        let displayName: String;
    }
    
    class SelectedItemCellView: UITableViewCell {

        let avatarView = AvatarView(frame: .zero);
        let label = UILabel();
        let subtext = UILabel();
    
        let textBox: UIStackView;
    
        private var cancellables: Set<AnyCancellable> = [];
        var contact: Contact? {
            didSet {
                cancellables.removeAll();
                contact?.$displayName.map({ $0 as String? }).receive(on: DispatchQueue.main).assign(to: \.text, on: label).store(in: &cancellables);
                if let contact = self.contact {
                    contact.$displayName.combineLatest(contact.avatarPublisher).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (name, avatar) in
                        self?.avatarView.set(name: name, avatar: avatar);
                    }).store(in: &cancellables);
                }
                self.subtext.text = contact?.jid.stringValue
            }
        }

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            self.textBox = UIStackView(arrangedSubviews: [label, subtext]);
            super.init(style: style, reuseIdentifier: reuseIdentifier);
            setup();
        }
        
        required init?(coder: NSCoder) {
            self.textBox = UIStackView(arrangedSubviews: [label, subtext]);
            super.init(coder: coder);
            setup();
        }
        
        private func setup() {
            self.autoresizesSubviews = true;
            self.avatarView.layer.masksToBounds = true;
            
            textBox.axis = .vertical;
            textBox.alignment = .fill;
            textBox.distribution = .fill;
            avatarView.translatesAutoresizingMaskIntoConstraints = false;
            textBox.translatesAutoresizingMaskIntoConstraints = false;
            addSubview(avatarView);
            addSubview(textBox);
            
            label.font = SelectedItemCellView.labelViewFont();
            label.adjustsFontForContentSizeCategory = true;
            subtext.font = UIFont.preferredFont(forTextStyle: .caption1)
            subtext.adjustsFontForContentSizeCategory = true;
            subtext.textColor = UIColor.secondaryLabel;

            NSLayoutConstraint.activate([
                self.avatarView.widthAnchor.constraint(equalTo: self.avatarView.heightAnchor),
                self.avatarView.heightAnchor.constraint(equalToConstant: 40),
                self.safeAreaLayoutGuide.leadingAnchor.constraint(equalTo: avatarView.leadingAnchor, constant: -10),
                self.safeAreaLayoutGuide.topAnchor.constraint(equalTo: avatarView.topAnchor, constant: -6),
                self.safeAreaLayoutGuide.bottomAnchor.constraint(greaterThanOrEqualTo: avatarView.bottomAnchor, constant: 6),
                
                avatarView.trailingAnchor.constraint(equalTo: textBox.leadingAnchor, constant: -8),
                self.centerYAnchor.constraint(equalTo: textBox.centerYAnchor),
                self.topAnchor.constraint(greaterThanOrEqualTo: textBox.topAnchor, constant: -6),
                
                self.safeAreaLayoutGuide.trailingAnchor.constraint(equalTo: textBox.trailingAnchor, constant: 10)
            ])
        }

        static func labelViewFont() -> UIFont {
            let preferredFont = UIFont.preferredFont(forTextStyle: .subheadline);
            let fontDescription = preferredFont.fontDescriptor.withSymbolicTraits(.traitBold)!;
            return UIFont(descriptor: fontDescription, size: preferredFont.pointSize);
        }
    }
    
}

protocol MultiContactSearchControllerDelegate: AnyObject {
    
    var selectedItems: [MultiContactSelectionViewController.Item] { get }
    
    func selected(item: MultiContactSelectionViewController.Item);
    
}
