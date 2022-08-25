// Copyright (c) 2020 XMLCoder contributors
//
// This software is released under the MIT License.
// https://opensource.org/licenses/MIT
//
//  Created by Max Desiatov on 09/04/2020.
//

import XCTest
import XMLCoder

final class CDATATest: XCTestCase {
    private struct Container: Codable, Equatable {
        let value: Int
        let data: String
    }

    private let xml =
        """
        <container>
           <value>42</value>
           <data><![CDATA[lorem ipsum]]></data>
        </container>
        """.data(using: .utf8)!

    func testXML() throws {
        let decoder = XMLDecoder()
        let result = try decoder.decode(Container.self, from: xml)

        XCTAssertEqual(result, Container(value: 42, data: "lorem ipsum"))
    }

    private struct CData: Codable {
        let string: String
        let int: Int
        let bool: Bool
        let commonString: String
        
        enum CodingKeys: String, CodingKey {
            case string
            case int
            case bool
            case commonString
        }
    }

    private let expectedCData =
        """
        <CData>
            <string><![CDATA[string]]></string>
            <int>123</int>
            <bool>true</bool>
            <commonString>commonString</commonString>
        </CData>
        """

    func testCDataTypes() throws {
        let example = CData(string: "string", int: 123, bool: true, commonString: "commonString")
        let xmlEncoder = XMLEncoder()
        xmlEncoder.CDataKeyWrapperStrategy = .custom({ key in
            key == CData.CodingKeys.string.rawValue
        })
        xmlEncoder.outputFormatting = .prettyPrinted
        let encoded = try xmlEncoder.encode(example)
        let result = String(data: encoded, encoding: .utf8)
        print(result!)
        XCTAssertEqual(result, expectedCData)
    }
}
