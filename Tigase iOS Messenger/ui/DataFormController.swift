//
// DataFormController.swift
//
// Tigase iOS Messenger
// Copyright (C) 2017 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import UIKit
import TigaseSwift


class DataFormController: UITableViewController {
    
    var form: JabberDataElement?;

    var errors = [IndexPath]();
    
    override func viewDidLoad() {
        super.viewDidLoad();
        tableView.register(TextSingleFieldCell.self, forCellReuseIdentifier: "FormViewCell-text-single");
        tableView.register(TextPrivateFieldCell.self, forCellReuseIdentifier: "FormViewCell-text-private");
        tableView.register(TextMultiFieldCell.self, forCellReuseIdentifier: "FormViewCell-text-multi");
        tableView.register(JidSingleFieldCell.self, forCellReuseIdentifier: "FormViewCell-jid-single");
        tableView.register(JidMultiFieldCell.self, forCellReuseIdentifier: "FormViewCell-jid-multi");
        tableView.register(BooleanFieldCell.self, forCellReuseIdentifier: "FormViewCell-boolean");
        tableView.register(FixedFieldCell.self, forCellReuseIdentifier: "FormViewCell-fixed");
        tableView.register(ListSingleFieldCell.self, forCellReuseIdentifier: "FormViewCell-list-single");
        tableView.register(ListMultiFieldCell.self, forCellReuseIdentifier: "FormViewCell-list-multi");
    }
    
    override func viewWillAppear(_ animated: Bool) {
        tableView.reloadData();
        super.viewWillAppear(animated);
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        guard form != nil else {
            return 0;
        }
        return 1;
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard form != nil else {
            return 0;
        }
        return form!.visibleFieldNames.count;
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let instructions: [String]? = form?.instructions as? [String];
        
        return (instructions == nil || instructions!.isEmpty) ? "Please fill this form" : instructions!.joined(separator: "\n");
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let fieldName = form!.visibleFieldNames[indexPath.row];
        let field = form!.getField(named: fieldName)!;
        let cellId = "FormViewCell-" + ( field.type ?? "fixed" );
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId, for: indexPath);
        (cell as? FieldCell)?.field = field;
        if field.type == "list-single" || field.type == "list-multi" || field.type == "text-multi" || field.type == "jid-multi" {
            cell.accessoryType = .disclosureIndicator;
        }
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        return nil;
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false);
        
        guard let fieldName = form?.visibleFieldNames[indexPath.row] else {
            return;
        }
        
        let field = form!.getField(named: fieldName)!;
        if field.type == "list-single" || field.type == "list-multi" {
            let listController = ListSelectorController(style: .grouped);
            listController.field = field as? ListField;
            self.navigationController?.pushViewController(listController, animated: true);
        } else if field.type == "text-multi" {
            let textController = TextController();
            textController.field = field as? TextMultiField;
            self.navigationController?.pushViewController(textController, animated: true);
        } else if field.type == "jid-multi" {
            let jidsController = JidsController();
            jidsController.field = field as? JidMultiField;
            self.navigationController?.pushViewController(jidsController, animated: true);
        }
    }
    
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if errors.index(where: { (idx)->Bool in
            return idx.row == indexPath.row && idx.section == indexPath.section
        }) != nil {
            let backgroundColor = cell.backgroundColor;
            UIView.animate(withDuration: 0.5, animations: {
                //cell.backgroundColor = UIColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 1);
                cell.backgroundColor = UIColor(hue: 0, saturation: 0.7, brightness: 0.8, alpha: 1)
            }, completion: {(b) in
                UIView.animate(withDuration: 0.5) {
                    cell.backgroundColor = backgroundColor;
                }
            });
        }
    }

    func validateForm() -> Bool {
        guard form != nil else {
            return false;
        }
        
        var errors = [IndexPath]();
        for (index, fieldName) in form!.visibleFieldNames.enumerated() {
            if let field = form!.getField(named: fieldName)! as? ValidatableField {
                if !field.valid {
                    errors.append(IndexPath(row: index, section: 0));
                }
            }
        }
        self.errors = errors;
        tableView.reloadRows(at: errors, with: .none);
        return errors.isEmpty;
    }
    
    func fillWithTestForm() {
        // For testing only!
        let form = JabberDataElement(type: .form);
        form.addField(TextSingleField(name: "username"));
        form.addField(TextPrivateField(name: "password"));
        form.addField(TextSingleField(name: "email"));
        form.addField(BooleanField(name: "policy", label: "Accept policy", value: true));
        form.addField(FixedField(name: "fixed 1", value: "Some random text to display which may be very long... and even longer..."));
        let hidden = HiddenField(name: "hidden-1");
        hidden.value = "some-value";
        form.addField(hidden);
        let singleList = ListSingleField(name: "role");
        singleList.options = [
            ListFieldOption(value: "admin", label: "Admin"),
            ListFieldOption(value: "user")
        ];
        singleList.value = "user";
        form.addField(singleList);
        let multiList = ListMultiField(name: "roles");
        multiList.options = [
            ListFieldOption(value: "admin", label: "Admin"),
            ListFieldOption(value: "user")
        ];
        multiList.value = ["user"];
        form.addField(multiList);
        let textMulti = TextMultiField(name: "description");
        textMulti.value = [ "First line", "Second line", "Third line" ];
        form.addField(textMulti);
        
        let jidSingle = JidSingleField(name: "buddy");
        jidSingle.value = JID("someone@example.com");
        form.addField(jidSingle);
        
        let jidMulti = JidMultiField(name: "spammers");
        jidMulti.value = [ JID("spammer1@example.com")!, JID("spammer2@example.com")! ];
        form.addField(jidMulti);
        
        self.form = form;
        tableView.reloadData();
    }
    
    class TextSingleFieldCell: AbstractTextSingleFieldCell {
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                guard let f: TextSingleField = field as? TextSingleField else {
                    value = nil;
                    return;
                }
                value = f.value;
            }
        }
        
        override func textDidChanged(textField: UITextField) {
            (field as? TextSingleField)?.value = textField.text;
        }
        
    }
    
    class TextPrivateFieldCell: AbstractTextSingleFieldCell {
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                uiTextField.isSecureTextEntry = true;
                guard let f: TextPrivateField = field as? TextPrivateField else {
                    value = nil;
                    return;
                }
                value = f.value;
            }
        }
        
        override func textDidChanged(textField: UITextField) {
            (field as? TextPrivateField)?.value = textField.text;
        }
        
    }
    
    class AbstractTextSingleFieldCell: AbstractFieldCell {
        
        var uiTextField: UITextField! {
            return fieldView as? UITextField;
        }
        
        override var fieldView: UIView? {
            didSet {
                uiTextField.addTarget(self, action: #selector(textDidChanged(textField:)), for: .editingChanged);
            }
        }
        
        var value: String? {
            get {
                return uiTextField.text;
            }
            set {
                uiTextField.text = newValue;
            }
        }
        
        override func createFieldView() -> UIView? {
            let field = UITextField();
            field.autocorrectionType = .no;
            field.autocapitalizationType = .none;
            return field;
        }
        
        @objc fileprivate func textDidChanged(textField: UITextField) {
            
        }
    }
    
    class TextMultiFieldCell: AbstractFieldCell {
        
        var uiTextField: UILabel! {
            return fieldView as? UILabel;
        }
        
        var value: String? {
            get {
                return uiTextField.text;
            }
            set {
                uiTextField.text = newValue;
            }
        }
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                guard let f: TextMultiField = field as? TextMultiField else {
                    value = nil;
                    return;
                }
                value = f.value.joined(separator: " ");
            }
        }
        
        override func createFieldView() -> UIView? {
            let label = UILabel();
            label.lineBreakMode = .byTruncatingTail;
            label.numberOfLines = 1;
            return label;
        }
    }
    
    class JidSingleFieldCell: AbstractFieldCell {
        var uiTextField: UITextField! {
            return fieldView as? UITextField;
        }
        
        override var fieldView: UIView? {
            didSet {
                uiTextField.addTarget(self, action: #selector(textDidChanged(textField:)), for: .valueChanged);
            }
        }
        
        var value: JID? {
            get {
                return JID(uiTextField.text);
            }
            set {
                uiTextField.text = newValue?.stringValue;
            }
        }
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                guard let f: JidSingleField = field as? JidSingleField else {
                    value = nil;
                    return;
                }
                value = f.value;
            }
        }
        
        override func createFieldView() -> UIView? {
            let field = UITextField();
            field.autocorrectionType = .no;
            field.autocapitalizationType = .none;
            field.keyboardType = .emailAddress;
            return field;
        }
        
        func textDidChanged(textField: UITextField) {
            (field as? JidSingleField)?.value = JID(textField.text);
        }
    }
    
    class JidMultiFieldCell: AbstractFieldCell {
        var uiTextField: UILabel! {
            return fieldView as? UILabel;
        }
        
        var value: [JID] {
            get {
                return uiTextField.text?.components(separatedBy: "\n").map({(str)->JID? in JID(str) }).filter({(jid)->Bool in jid != nil}).map({(jid)->JID in jid!}) ?? [JID]();
            }
            set {
                uiTextField.text = newValue.map({(jid)->String in jid.stringValue}).joined(separator: " ");
            }
        }
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                guard let f: JidMultiField = field as? JidMultiField else {
                    value = [];
                    return;
                }
                value = f.value;
            }
        }
        
        
        override func createFieldView() -> UIView? {
            return UILabel();
        }
    }
    
    class BooleanFieldCell: AbstractFieldCell {
        
        var uiSwitch: UISwitch! {
            return fieldView as? UISwitch;
        }
        
        override var fieldView: UIView? {
            didSet {
                uiSwitch.addTarget(self, action: #selector(switchValueChanged(switch:)), for: .valueChanged);
            }
        }
        
        var value: Bool {
            get {
                return uiSwitch.isOn;
            }
            set {
                uiSwitch.isOn = newValue;
            }
        }
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                value = (field as? BooleanField)?.value ?? false;
            }
        }
        
        override func createFieldView() -> UIView? {
            return UISwitch();
        }
        
        override func initialize(field: UIView?) {
            self.fieldView = field;
            accessoryView = field;
        }
        
        @objc func switchValueChanged(switch uiswitch: UISwitch) {
            (field as? BooleanField)?.value = uiswitch.isOn;
        }
        
    }
    
    class FixedFieldCell: AbstractFieldCell {
        
        override var label: String? {
            get { return nil; }
            set { }
        }
        
        var value: String? {
            get {
                return self.textLabel?.text;
            }
            set {
                self.textLabel?.text = newValue;
                self.textLabel?.sizeToFit();
            }
        }
        
        override var field: Field? {
            didSet {
                //label = field?.label ?? field?.name.capitalized;
                value = (field as? FixedField)?.value;
            }
        }
        
        override func createFieldView() -> UIView? {
            textLabel?.lineBreakMode = .byWordWrapping;
            textLabel?.numberOfLines = 0;
            return nil;
        }
    }
    
    class ListSingleFieldCell: AbstractFieldCell {
        
        var value: String? {
            get {
                return (fieldView as? UILabel)?.text;
            }
            set {
                (fieldView as? UILabel)?.text = newValue;
            }
        }
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                if let f: ListSingleField = field as? ListSingleField {
                    let value = f.value;
                    let selected = f.options.first(where: { (option) -> Bool in
                        option.value == value;
                    });
                    self.value = selected?.label ?? selected?.value;
                }
            }
        }
        
        override func createFieldView() -> UIView? {
            let label = UILabel();
            label.textAlignment = .right;
            return label;
        }
    }
    
    class ListMultiFieldCell: AbstractFieldCell {
        
        var value: String? {
            get {
                return (fieldView as? UILabel)?.text;
            }
            set {
                (fieldView as? UILabel)?.text = newValue;
            }
        }
        
        override var field: Field? {
            didSet {
                label = field?.label ?? field?.name.capitalized;
                if let f: ListMultiField = field as? ListMultiField {
                    let value = f.value;
                    let selected = f.options.filter({ (option) -> Bool in
                        return value.index(of: option.value) != nil;
                    });
                    self.value = selected.map({ (option) -> String in
                        option.label ?? option.value
                    }).joined(separator: ", ");
                }
            }
        }
        
        override func createFieldView() -> UIView? {
            let label = UILabel();
            return label;
        }
    }
    
    class AbstractFieldCell: UITableViewCell, FieldCell {
        
        var label: String? {
            get {
                return self.textLabel?.text;
            }
            set {
                self.textLabel?.text = newValue;
            }
        }
        
        var field: Field?;
        var fieldView: UIView?;
        
        override init(style: UITableViewCellStyle, reuseIdentifier: String?) {
            super.init(style: UITableViewCellStyle.value1, reuseIdentifier: reuseIdentifier);
            initialize(field: createFieldView());
        }
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder);
            initialize(field: createFieldView());
            initialize(field: fieldView);
        }
        
        func initialize(field: UIView?) {
            self.fieldView = field;
            guard field != nil else {
                return;
            }
            field!.translatesAutoresizingMaskIntoConstraints = false;
            contentView.addSubview(field!);
            addConstraints([
                NSLayoutConstraint(item: field!, attribute: .leading, relatedBy: .equal, toItem: textLabel, attribute: .trailing, multiplier: 1, constant: 8),
                NSLayoutConstraint(item: field!, attribute: .top, relatedBy: .equal, toItem: contentView, attribute: .top, multiplier: 1, constant: 8),
                NSLayoutConstraint(item: field!, attribute: .bottom, relatedBy: .equal, toItem: contentView, attribute: .bottom, multiplier: 1, constant: -8),
                NSLayoutConstraint(item: field!, attribute: .trailing, relatedBy: .equal, toItem: contentView, attribute: .trailing, multiplier: 1, constant: -8)
                ]);
            (field as? UITextField)?.textAlignment = .right;
            (field as? UILabel)?.textAlignment = .right;
        }
        
        func createFieldView() -> UIView? {
            return nil;
        }
    }
    
    class ListSelectorController: UITableViewController {
        
        var field: ListField! {
            didSet {
                options = field.options;
            }
        }
        
        var options: [ListFieldOption] = [];
        
        override func viewDidLoad() {
            tableView.allowsSelection = true;
            tableView.allowsMultipleSelection = (field as? ListMultiField) != nil;
        }
        
        override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            return field.options.count;
        }
        
        override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
            return (field as? Field)?.label ?? (field as? Field)?.name.capitalized;
        }
        
        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil);
            let option = options[indexPath.row];
            cell.textLabel?.text = option.label ?? option.value;
            return cell;
        }
        
        override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
            let option = options[indexPath.row];
            if let multiList: ListMultiField = field as? ListMultiField {
                let values = multiList.value;
                cell.accessoryType = values.index(of: option.value) != nil ? .checkmark : .none;
            } else if let singleList: ListSingleField = field as? ListSingleField {
                cell.accessoryType = singleList.value == option.value ? .checkmark : .none;
            }
        }
        
        override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true);
            let value = options[indexPath.row].value;
            if let multiList: ListMultiField = field as? ListMultiField {
                var values = multiList.value;
                if let idx = values.index(of: value) {
                    values.remove(at: idx);
                } else {
                    values.append(value);
                }
                multiList.value = values;
            } else if let singleList: ListSingleField = field as? ListSingleField {
                if singleList.value == value {
                    singleList.value = nil;
                } else {
                    singleList.value = value;
                }
            }
            tableView.reloadData();
        }
        
    }
    
    class JidsController:  UIViewController, UITextViewDelegate {
        
        var textView = UITextView();
        
        var field: JidMultiField! {
            didSet {
                textView.text = field.value.map({(jid)->String in jid.stringValue}).joined(separator: "\n");
            }
        }
        
        override func viewDidLoad() {
            textView.delegate = self;
            textView.allowsEditingTextAttributes = false;
            textView.autocorrectionType = .no;
            textView.autocapitalizationType = .none;
            
            super.viewDidLoad();
            
            textView.translatesAutoresizingMaskIntoConstraints = false;
            view.addSubview(textView);
            view.addConstraints([
                NSLayoutConstraint(item: textView, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 8),
                NSLayoutConstraint(item: textView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 8),
                NSLayoutConstraint(item: textView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: -8),
                NSLayoutConstraint(item: textView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 8)
                ]);
        }
        
        func textViewDidChange(_ textView: UITextView) {
            let values = textView.text.components(separatedBy: "\n");
            let results = values.map({(str)->JID? in JID(str) }).filter({(jid)->Bool in jid != nil}).map({(jid)->JID in jid!});
            field.value = results;
        }
        
    }
    
    class TextController:  UIViewController, UITextViewDelegate {
        
        var textView = UITextView();
        
        var field: TextMultiField! {
            didSet {
                textView.text = field.rawValue.joined(separator: "\n");
            }
        }
        
        override func viewDidLoad() {
            textView.delegate = self;
            textView.allowsEditingTextAttributes = false;
            textView.autocorrectionType = .no;
            textView.autocapitalizationType = .none;
            
            super.viewDidLoad();
            
            textView.translatesAutoresizingMaskIntoConstraints = false;
            view.addSubview(textView);
            view.addConstraints([
                NSLayoutConstraint(item: textView, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 8),
                NSLayoutConstraint(item: textView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 8),
                NSLayoutConstraint(item: textView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: -8),
                NSLayoutConstraint(item: textView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 8)
                ]);
        }
        
        func textViewDidChange(_ textView: UITextView) {
            field.value = textView.text.components(separatedBy: "\n");
        }
        
    }

}

protocol FieldCell: class {
    
    var field: Field? {
        get set
    }
    
}
