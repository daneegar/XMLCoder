// Copyright (c) 2018-2020 XMLCoder contributors
//
// This software is released under the MIT License.
// https://opensource.org/licenses/MIT
//
//  Created by Vincent Esche on 12/18/18.
//

import Foundation

struct XMLCoderElement: Equatable {
    struct Attribute: Equatable {
        let key: String
        let value: String
    }

    let key: String
    private(set) var stringValue: String?
    private(set) var elements: [XMLCoderElement] = []
    private(set) var attributes: [Attribute] = []
    private(set) var containsTextNodes: Bool = false

    var isStringNode: Bool {
        return key == ""
    }

    var isCDATANode: Bool {
        return key == "#CDATA"
    }

    var isTextNode: Bool {
        return isStringNode || isCDATANode
    }

    init(
        key: String,
        elements: [XMLCoderElement] = [],
        attributes: [Attribute] = []
    ) {
        self.key = key
        stringValue = nil
        self.elements = elements
        self.attributes = attributes
    }

    init(
        key: String,
        stringValue string: String,
        attributes: [Attribute] = []
    ) {
        self.key = key
        elements = [XMLCoderElement(stringValue: string)]
        self.attributes = attributes
        containsTextNodes = true
    }

    init(
        key: String,
        cdataValue string: String,
        attributes: [Attribute] = []
    ) {
        self.key = key
        elements = [XMLCoderElement(cdataValue: string)]
        self.attributes = attributes
        containsTextNodes = true
    }

    init(stringValue string: String) {
        key = ""
        stringValue = string
    }

    init(cdataValue string: String) {
        key = "#CDATA"
        stringValue = string
    }

    mutating func append(element: XMLCoderElement) {
        elements.append(element)
        containsTextNodes = containsTextNodes || element.isTextNode
    }

    mutating func append(string: String) {
        if elements.last?.isTextNode == true {
            let oldValue = elements[elements.count - 1].stringValue ?? ""
            elements[elements.count - 1].stringValue = oldValue + string
        } else {
            elements.append(XMLCoderElement(stringValue: string))
        }
        containsTextNodes = true
    }

    mutating func append(cdata string: String) {
        if elements.last?.isCDATANode == true {
            let oldValue = elements[elements.count - 1].stringValue ?? ""
            elements[elements.count - 1].stringValue = oldValue + string
        } else {
            elements.append(XMLCoderElement(cdataValue: string))
        }
        containsTextNodes = true
    }

    mutating func trimTextNodes() {
        guard containsTextNodes else { return }
        for idx in elements.indices {
            elements[idx].stringValue = elements[idx].stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func transformToBoxTree() -> Box {
        if isTextNode {
            return StringBox(stringValue!)
        }

        let attributes = KeyedStorage(self.attributes.map { attribute in
            (key: attribute.key, value: StringBox(attribute.value) as SimpleBox)
        })
        let storage = KeyedStorage<String, Box>()
        let elements = self.elements.reduce(storage) { $0.merge(element: $1) }
        return KeyedBox(elements: elements, attributes: attributes)
    }

    func toXMLString(
        with header: XMLHeader? = nil,
        escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        formatting: XMLEncoder.OutputFormatting,
        indentation: XMLEncoder.PrettyPrintIndentation
    ) -> String {
        if let header = header, let headerXML = header.toXML() {
            return headerXML + _toXMLString(escapedCharacters, formatting, indentation)
        }
        return _toXMLString(escapedCharacters, formatting, indentation)
    }

    private func formatUnsortedXMLElements(
        _ string: inout String,
        _ level: Int,
        _ escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        _ formatting: XMLEncoder.OutputFormatting,
        _ indentation: XMLEncoder.PrettyPrintIndentation,
        _ prettyPrinted: Bool
    ) {
        formatXMLElements(
            from: elements,
            into: &string,
            at: level,
            escapedCharacters: escapedCharacters,
            formatting: formatting,
            indentation: indentation,
            prettyPrinted: prettyPrinted
        )
    }

    fileprivate func elementString(
        for element: XMLCoderElement,
        at level: Int,
        formatting: XMLEncoder.OutputFormatting,
        indentation: XMLEncoder.PrettyPrintIndentation,
        escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        prettyPrinted: Bool
    ) -> String {
        if let stringValue = element.stringValue {
            if element.isCDATANode {
                return "<![CDATA[\(stringValue)]]>"
            } else {
                return stringValue.escape(escapedCharacters.elements)
            }
        }

        var string = ""
        string += element._toXMLString(indented: level + 1, escapedCharacters, formatting, indentation)
        string += prettyPrinted ? "\n" : ""
        return string
    }

    fileprivate func formatSortedXMLElements(
        _ string: inout String,
        _ level: Int,
        _ escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        _ formatting: XMLEncoder.OutputFormatting,
        _ indentation: XMLEncoder.PrettyPrintIndentation,
        _ prettyPrinted: Bool
    ) {
        formatXMLElements(from: elements.sorted { $0.key < $1.key },
                          into: &string,
                          at: level,
                          escapedCharacters: escapedCharacters,
                          formatting: formatting,
                          indentation: indentation,
                          prettyPrinted: prettyPrinted)
    }

    fileprivate func formatXMLAttributes(
        from attributes: [Attribute],
        into string: inout String,
        charactersEscapedInAttributes: [(String, String)]
    ) {
        for attribute in attributes {
            string += " \(attribute.key)=\"\(attribute.value.escape(charactersEscapedInAttributes))\""
        }
    }

    fileprivate func formatXMLElements(
        from elements: [XMLCoderElement],
        into string: inout String,
        at level: Int,
        escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        formatting: XMLEncoder.OutputFormatting,
        indentation: XMLEncoder.PrettyPrintIndentation,
        prettyPrinted: Bool
    ) {
        for element in elements {
            string += elementString(for: element,
                                    at: level,
                                    formatting: formatting,
                                    indentation: indentation,
                                    escapedCharacters: escapedCharacters,
                                    prettyPrinted: prettyPrinted && !containsTextNodes)
        }
    }

    private func formatXMLAttributes(
        _ formatting: XMLEncoder.OutputFormatting,
        _ string: inout String,
        _ charactersEscapedInAttributes: [(String, String)]
    ) {
        let attributesBelongingToContainer = self.elements.filter {
            $0.key.isEmpty && !$0.attributes.isEmpty
        }.flatMap {
            $0.attributes
        }
        let allAttributes = self.attributes + attributesBelongingToContainer

        let attributes = formatting.contains(.sortedKeys) ?
            allAttributes.sorted(by: { $0.key < $1.key }) :
            allAttributes
        formatXMLAttributes(
            from: attributes,
            into: &string,
            charactersEscapedInAttributes: charactersEscapedInAttributes
        )
    }

    private func formatXMLElements(
        _ escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        _ formatting: XMLEncoder.OutputFormatting,
        _ indentation: XMLEncoder.PrettyPrintIndentation,
        _ string: inout String,
        _ level: Int,
        _ prettyPrinted: Bool
    ) {
        if formatting.contains(.sortedKeys) {
            formatSortedXMLElements(
                &string, level, escapedCharacters, formatting, indentation, prettyPrinted
            )
            return
        }
        formatUnsortedXMLElements(
            &string, level, escapedCharacters, formatting, indentation, prettyPrinted
        )
    }

    private func _toXMLString(
        indented level: Int = 0,
        _ escapedCharacters: (elements: [(String, String)], attributes: [(String, String)]),
        _ formatting: XMLEncoder.OutputFormatting,
        _ indentation: XMLEncoder.PrettyPrintIndentation
    ) -> String {
        let prettyPrinted = formatting.contains(.prettyPrinted)
        let prefix: String
        switch indentation {
        case let .spaces(count) where prettyPrinted:
            prefix = String(repeating: " ", count: level * count)
        case let .tabs(count) where prettyPrinted:
            prefix = String(repeating: "\t", count: level * count)
        default:
            prefix = ""
        }
        var string = prefix

        if !key.isEmpty && !isCDATANode {
            string += "<\(key)"
            formatXMLAttributes(formatting, &string, escapedCharacters.attributes)
        }

        if !elements.isEmpty {
            let prettyPrintElements = prettyPrinted && !containsTextNodes
            if !key.isEmpty {
                string += prettyPrintElements ? ">\n" : ">"
            }
            formatXMLElements(escapedCharacters, formatting, indentation, &string, level, prettyPrintElements)

            if prettyPrintElements { string += prefix }
            if !key.isEmpty && !isCDATANode {
                string += "</\(key)>"
            }
        } else {
            if !key.isEmpty {
                string += " />"
            }
        }

        return string
    }
}

// MARK: - Convenience Initializers

extension XMLCoderElement {
    init(key: String, CDATAResolver: (KeyedBox.Key) -> Bool, unkeyedBox: UnkeyedBox, attributes: [Attribute] = []) {
        if let containsChoice = unkeyedBox as? [ChoiceBox] {
            self.init(
                key: key,
                elements: containsChoice.map {
                    XMLCoderElement(key: $0.key, CDATAResolver: CDATAResolver, box: $0.element)
                },
                attributes: attributes
            )
        } else {
            self.init(
                key: key,
                elements: unkeyedBox.map { XMLCoderElement(key: key, CDATAResolver: CDATAResolver, box: $0) },
                attributes: attributes
            )
        }
    }

    init(key: String, CDATAResolver: (KeyedBox.Key) -> Bool, choiceBox: ChoiceBox, attributes: [Attribute] = []) {
        self.init(
            key: key,
            elements: [
                XMLCoderElement(key: choiceBox.key, CDATAResolver: CDATAResolver, box: choiceBox.element),
            ],
            attributes: attributes
        )
    }

    init(key: String, CDATAResolver: (KeyedBox.Key) -> Bool, keyedBox: KeyedBox, attributes: [Attribute] = []) {
        var elements: [XMLCoderElement] = []

        for (key, box) in keyedBox.elements {
            let fail = {
                preconditionFailure("Unclassified box: \(type(of: box))")
            }
            switch box {
            case let sharedUnkeyedBox as SharedBox<UnkeyedBox>:
                let box = sharedUnkeyedBox.unboxed
                elements.append(contentsOf: box.map {
                    XMLCoderElement(key: key, CDATAResolver: CDATAResolver, box: $0)
                })
            case let unkeyedBox as UnkeyedBox:
                // This basically injects the unkeyed children directly into self:
                elements.append(contentsOf: unkeyedBox.map {
                    XMLCoderElement(key: key, CDATAResolver: CDATAResolver, box: $0)
                })
            case let sharedKeyedBox as SharedBox<KeyedBox>:
                let box = sharedKeyedBox.unboxed
                elements.append(XMLCoderElement(key: key, CDATAResolver: CDATAResolver, box: box))
            case let keyedBox as KeyedBox:
                elements.append(XMLCoderElement(key: key, CDATAResolver: CDATAResolver, box: keyedBox))
            case let simpleBox as SimpleBox:
                elements.append(XMLCoderElement(key: key, CDATAResolver: CDATAResolver, box: simpleBox))
            default:
                fail()
            }
        }

        let attributes: [Attribute] = attributes + keyedBox.attributes.compactMap { key, box in
            guard let value = box.xmlString else {
                return nil
            }
            return Attribute(key: key, value: value)
        }

        self.init(key: key, elements: elements, attributes: attributes)
    }

    init(key: String, CDATAResolver: (KeyedBox.Key) -> Bool, box: SimpleBox) {
        if CDATAResolver(key), let stringBox = box as? StringBox {
            self.init(key: key, cdataValue: stringBox.unboxed)
        } else if let value = box.xmlString {
            self.init(key: key, stringValue: value)
        } else {
            self.init(key: key)
        }
    }

    init(key: String, CDATAResolver: (KeyedBox.Key) -> Bool, box: Box, attributes: [Attribute] = []) {
        switch box {
        case let sharedUnkeyedBox as SharedBox<UnkeyedBox>:
            self.init(key: key, CDATAResolver: CDATAResolver, unkeyedBox: sharedUnkeyedBox.unboxed, attributes: attributes)
        case let sharedKeyedBox as SharedBox<KeyedBox>:
            self.init(key: key, CDATAResolver: CDATAResolver, box: sharedKeyedBox.unboxed, attributes: attributes)
        case let sharedChoiceBox as SharedBox<ChoiceBox>:
            self.init(key: key, CDATAResolver: CDATAResolver, box: sharedChoiceBox.unboxed, attributes: attributes)
        case let unkeyedBox as UnkeyedBox:
            self.init(key: key, CDATAResolver: CDATAResolver, unkeyedBox: unkeyedBox, attributes: attributes)
        case let keyedBox as KeyedBox:
            self.init(key: key, CDATAResolver: CDATAResolver, keyedBox: keyedBox, attributes: attributes)
        case let choiceBox as ChoiceBox:
            self.init(key: key, CDATAResolver: CDATAResolver, choiceBox: choiceBox, attributes: attributes)
        case let simpleBox as SimpleBox:
            self.init(key: key, CDATAResolver: CDATAResolver, box: simpleBox)
        case let box:
            preconditionFailure("Unclassified box: \(type(of: box))")
        }
    }
}

extension XMLCoderElement {
    func isWhitespaceWithNoElements() -> Bool {
        let stringValueIsWhitespaceOrNil = stringValue?.isAllWhitespace() ?? true
        return self.key == "" && stringValueIsWhitespaceOrNil && self.elements.isEmpty
    }
}
