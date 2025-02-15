//
//  DataTypeTests.swift
//  LucidTests
//
//  Created by Stephane Magne on 6/26/20.
//  Copyright © 2020 Scribd. All rights reserved.
//

import XCTest

@testable import Lucid
@testable import LucidTestKit

final class DataTypeTests: XCTestCase {

    func test_encoding_and_decoding_a_lazy_value() {

        struct Object: Codable, Equatable {
            let name: String
            let age: Int
            let petName: Lazy<String>
        }

        let object1 = Object(name: "Steve", age: 40, petName: .unrequested)
        let object2 = Object(name: "Bob", age: 45, petName: .requested("GoodDog"))

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let encodedData1 = try encoder.encode(object1)
            let encodedData2 = try encoder.encode(object2)

            let decodedObject1 = try decoder.decode(Object.self, from: encodedData1)
            let decodedObject2 = try decoder.decode(Object.self, from: encodedData2)
            
            XCTAssertEqual(object1, decodedObject1)
            XCTAssertEqual(object2, decodedObject2)
        } catch {
            XCTFail("failed with error \(error)")
        }
    }
}
