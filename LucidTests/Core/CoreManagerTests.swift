//
//  CoreManagerTests.swift
//  LucidTests
//
//  Created by Théophane Rupin on 12/10/18.
//  Copyright © 2018 Scribd. All rights reserved.
//

import Foundation
import Combine
import XCTest

@testable import Lucid
@testable import LucidTestKit

final class CoreManagerTests: XCTestCase {

    private var remoteStoreSpy: StoreSpy<EntitySpy>!

    private var memoryStoreSpy: StoreSpy<EntitySpy>!

    private var manager: CoreManaging<EntitySpy, AnyEntitySpy>!

    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()

        LucidConfiguration.logger = LoggerMock(shouldCauseFailures: false)

        remoteStoreSpy = StoreSpy()
        remoteStoreSpy.levelStub = .remote

        memoryStoreSpy = StoreSpy()
        memoryStoreSpy.levelStub = .memory

        cancellables = Set()

        manager = CoreManager(stores: [remoteStoreSpy.storing, memoryStoreSpy.storing]).managing()
    }

    override func tearDown() {
        defer { super.tearDown() }

        remoteStoreSpy = nil
        memoryStoreSpy = nil
        manager = nil
        cancellables = nil
    }

    // MARK: - get(byID:in:cacheStrategy:completion:)

    func test_manager_should_get_entity_from_remote_store_then_cache_it_when_cache_strategy_is_prefer_remote() {

        remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.entity?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entity_from_remote_store_then_not_cache_it_and_fall_back_to_memory_store_when_cache_strategy_is_prefer_remote() {

        remoteStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        memoryStoreSpy.getResultStub = .success(.empty())

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remoteOrLocal(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api(.api(httpStatusCode: 500, errorPayload: nil, _)))):
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entity_from_remote_store_then_not_cache_it_when_data_source_is_remote() {

        remoteStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let onceExpectation = self.expectation(description: "once")

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api(.api(httpStatusCode: 500, errorPayload: nil, _)))):
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 0)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entity_from_remote_store_only_when_cache_strategy_is_remote_only() {

        remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.entity?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entity_from_remote_store_when_cache_strategy_is_remote_only() {

        remoteStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        memoryStoreSpy.getResultStub = .success(.empty())

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api(.api(httpStatusCode: 500, errorPayload: nil, _)))):
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 0)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entity_from_memory_store_only_when_strategy_is_cache_only() {

        memoryStoreSpy.getResultStub = .success(.empty())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .local)

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertNil(result.entity)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entity_from_memory_store_then_not_cache_it_when_strategy_is_cache_only() {

        memoryStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .local)

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.entity?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entity_from_memory_store_then_not_cache_it_when_strategy_is_cache_only() {

        memoryStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .local)

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api(.api(httpStatusCode: 500, errorPayload: nil, _)))):
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 0)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entity_from_memory_first_then_from_remote_store_when_strategy_is_prefer_cache() {

        memoryStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])
        remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.entity?.identifier.value.remoteValue, 42)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.last?.identifier.value.remoteValue, 42)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_not_get_entity_from_memory_first_but_still_reach_remote_store_when_strategy_is_prefer_cache() {

        memoryStoreSpy.getResultStub = .success(.empty())
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])
        remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertNotNil(result.entity)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_not_return_nil_from_cache_but_should_return_nil_from_remote_store_when_strategy_is_prefer_cache() {

        memoryStoreSpy.getResultStub = .success(.empty())
        memoryStoreSpy.removeResultStub = .success(())
        remoteStoreSpy.getResultStub = .success(.empty())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertNil(result.entity)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entity_from_memory_first_but_ignore_error_and_reach_remote_store_when_strategy_is_prefer_cache() {

        memoryStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])
        remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil))))

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {

                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entity_from_memory_first_but_ignore_error_and_return_remote_store_error_when_strategy_is_prefer_cache() {

        memoryStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        remoteStoreSpy.getResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        let onceExpectation = self.expectation(description: "once")

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api(.api(httpStatusCode: 500, errorPayload: nil, _)))):
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                    XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {

                        XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                        onceExpectation.fulfill()
                    }
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completed")
                }
            }, receiveValue: { result in
                XCTFail("Unexpected success")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_returns_local_values_if_local_result_count_matches_identifier_count_when_observing_once_signal_and_strategy_is_prefer_cache() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil))]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil)), EntitySpy(idValue: .remote(44, nil))]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("ids", .value(["42", "43"]))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 43)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_returns_remote_values_if_local_result_count_does_not_match_identifier_count_when_observing_once_signal_and_strategy_is_prefer_cache() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil))]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil))]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("ids", .value(["42", "43"]))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]

        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 43)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_returns_both_remote_results_and_local_results_when_observing_continuous_signal_and_strategy_is_prefer_cache() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil))]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil))]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(43, nil))])

        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2

        var continuousCallCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("ids", .value(["42", "43"]))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion")
                }
            }, receiveValue: { result in
                if continuousCallCount == 0 {
                    XCTAssertEqual(result.count, 1)
                    XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                } else {
                    XCTAssertEqual(result.count, 2)
                    XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                    XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 43)
                }
                continuousCallCount += 1
                continuousExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [continuousExpectation], timeout: 1)
    }

    func test_manager_continuous_observer_emits_once_when_results_are_the_same() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil))]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil))]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let continuousExpectation = self.expectation(description: "continuous")

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("ids", .value(["42", "43"]))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion")
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                continuousExpectation.fulfill()
            })
            .store(in: &cancellables)

        let waitExpectation = self.expectation(description: "wait")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            waitExpectation.fulfill()
        }

        wait(for: [continuousExpectation, waitExpectation], timeout: 1)
    }

    // MARK: - search(withQuery:context:cacheStrategy:completion:)

    func test_manager_should_get_entities_from_remote_store_then_cache_them_when_strategy_is_prefer_remote() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 2)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 1)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entities_when_remote_store_fails_and_strategy_is_prefer_remote() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]))
        memoryStoreSpy.searchResultStub = .failure(.notSupported)
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 2)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 1)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entities_when_stores_fails_and_strategy_is_prefer_remote() {

        remoteStoreSpy.searchResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        memoryStoreSpy.searchResultStub = .failure(.notSupported)

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remoteOrLocal(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.composite(current: .notSupported, previous: .api))):
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completed.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_v3_manager_should_fail_to_get_entities_when_stores_fails_and_data_source_is_remote() {

        remoteStoreSpy.searchResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        memoryStoreSpy.searchResultStub = .failure(.notSupported)

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let onceExpectation = self.expectation(description: "once")

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api(.api(httpStatusCode: 500, errorPayload: nil, _)))):
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completed.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }
    func test_manager_should_get_entities_from_remote_store_when_strategy_is_remote_only() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entities_when_remote_store_fails_and_strategy_is_remote_only() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]))
        memoryStoreSpy.searchResultStub = .failure(.notSupported)
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_fail_to_get_entities_when_stores_fails_and_strategy_is_remote_only() {

        remoteStoreSpy.searchResultStub = .failure(.api(.api(
            httpStatusCode: 500, errorPayload: nil, response: APIClientResponse(data: Data(), cachedResponse: false)
        )))
        memoryStoreSpy.searchResultStub = .failure(.notSupported)

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(.store(.api)):
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                    onceExpectation.fulfill()
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completed.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entities_from_memory_store_then_not_cache_them_when_strategy_is_cache() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]))

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .local)

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_manager_should_get_entities_from_memory_then_remote_store_when_strategy_is_prefer_cache() {

        let entities = [EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]
        memoryStoreSpy.searchResultStub = .success(.entities(entities))
        remoteStoreSpy.searchResultStub = .success(.entities(entities))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    XCTAssertEqual(self.memoryStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                    XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 2)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 2)
                    XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)

    }

    func test_manager_should_ignore_empty_entities_from_memory_then_get_entities_from_remote_store_when_strategy_is_prefer_cache() {

        let entities = [EntitySpy(idValue: .remote(42, nil)), EntitySpy(idValue: .remote(42, nil))]
        memoryStoreSpy.searchResultStub = .success(.entities([]))
        remoteStoreSpy.searchResultStub = .success(.entities(entities))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.array.last?.identifier.value.remoteValue, 42)
                XCTAssertEqual(result.count, 2)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    XCTAssertEqual(self.memoryStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                    XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 2)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 2)
                    XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: - Providers

    func test_manager_should_send_entity_update_to_provider_when_strategy_is_prefer_cache() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")]))

        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.title, "fake_title")
                XCTAssertEqual(result.count, 1)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    XCTAssertEqual(self.memoryStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                    XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 2)
                    XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                    XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                    onceExpectation.fulfill()
                }
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    Logger.log(.debug, "Did complete")
                }
            }, receiveValue: { result in
                if continuousCallCount == 0 {
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)
                } else {
                    XCTAssertEqual(result.first?.title, "updated_fake_title")
                    XCTAssertEqual(result.count, 1)
                }
                continuousCallCount += 1
                continuousExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_send_entity_update_to_provider_when_entity_changed() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        dispatchQueue.sync {
            publishers
                .once
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        onceExpectation.fulfill()
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)

                    self.remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")))
                    self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

                    let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                        endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                        persistenceStrategy: .persist(.discardExtraLocalData)
                    ))
                    self.manager
                        .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    onceExpectation.fulfill()
                })
                .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                    } else {
                        XCTAssertEqual(result.first?.title, "updated_fake_title")
                        XCTAssertEqual(result.count, 1)
                    }
                    continuousCallCount += 1
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)
        }

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_not_send_entity_update_to_provider_when_entity_did_not_change() {

        let entity = EntitySpy(idValue: .remote(42, nil), title: "fake_title")
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        var continuousCount = 0
        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.title, "fake_title")
                XCTAssertEqual(result.count, 1)

                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: entity))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
            }, receiveValue: { result in
                if continuousCount == 0 {
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)
                    continuousExpectation.fulfill()
                } else {
                    XCTFail("Received too many updates")
                }
                continuousCount += 1
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)

        let additionalSignalExpectation = self.expectation(description: "additional")

        DispatchQueue(label: "test").asyncAfter(deadline: .now() + .milliseconds(100)) {
            additionalSignalExpectation.fulfill()
        }

        wait(for: [additionalSignalExpectation], timeout: 1.0)
    }

    func test_manager_should_send_entity_update_to_provider_with_different_query_when_entity_changed() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("query", .value("fake_title"))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.title ~= .string(".*fake_title")), in: context)

        dispatchQueue.sync {
            publishers
                .once
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        onceExpectation.fulfill()
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)

                    self.remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")))
                    self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
                    let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                        endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                        persistenceStrategy: .persist(.discardExtraLocalData)
                    ))
                    self.manager
                        .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    onceExpectation.fulfill()
                })
                .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                    } else {
                        XCTAssertEqual(result.first?.title, "updated_fake_title")
                        XCTAssertEqual(result.count, 1)
                    }
                    continuousCallCount += 1
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)
        }

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_send_entity_update_to_provider_with_different_query_when_entity_is_not_in_filter_anymore() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("query", .value("fake_title"))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.title == .string("fake_title")), in: context)

        dispatchQueue.sync {
            publishers
                .once
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        onceExpectation.fulfill()
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)

                    self.remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")))
                    self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
                    let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                        endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                        persistenceStrategy: .persist(.discardExtraLocalData)
                    ))
                    self.manager
                        .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    onceExpectation.fulfill()
                })
                .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                    } else {
                        XCTAssertEqual(result.count, 0)
                    }
                    continuousCallCount += 1
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)
        }

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_not_send_entity_update_to_provider_with_different_query_when_entity_did_not_change() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("query", .value("fake_title"))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.title == .string("fake_title")), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.title, "fake_title")
                XCTAssertEqual(result.count, 1)

                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil), title: "fake_title")))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    Logger.log(.debug, "Did complete")
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.title, "fake_title")
                XCTAssertEqual(result.count, 1)
                continuousExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_send_entity_update_to_provider_with_different_query_when_entity_is_not_found() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("query", .value("fake_title"))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.title == .string("fake_title")), in: context)

        dispatchQueue.sync {
            publishers
                .once
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        onceExpectation.fulfill()
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)

                    self.memoryStoreSpy.getResultStub = .success(.empty())
                    self.memoryStoreSpy.removeResultStub = .success(())
                    self.remoteStoreSpy.getResultStub = .success(.empty())
                    self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
                    let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                        endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                        persistenceStrategy: .persist(.discardExtraLocalData)
                    ))
                    self.manager
                        .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    onceExpectation.fulfill()
                })
                .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                    } else {
                        XCTAssertEqual(result.count, 0)
                    }
                    continuousCallCount += 1
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)
        }

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_send_entity_update_to_provider_when_entity_is_removed() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("query", .value("fake_title"))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.title == .string("fake_title")), in: context)

        dispatchQueue.sync {
            publishers
                .once
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        onceExpectation.fulfill()
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)

                    self.memoryStoreSpy.removeResultStub = .success(())
                    self.remoteStoreSpy.removeResultStub = .success(())
                    self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
                    self.manager
                        .remove(atID: EntitySpyIdentifier(value: .remote(42, nil)), in: WriteContext(dataTarget: .local))
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    onceExpectation.fulfill()
                })
                .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                    } else {
                        XCTAssertEqual(result.count, 0)
                    }
                    continuousCallCount += 1
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)
        }

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_send_entity_update_to_provider_when_entity_is_set() {

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2
        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(
                method: .get,
                path: .path("fake_entity"),
                query: [("query", .value("fake_title"))]
            ), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.title ~= .string(".*fake_title")), in: context)

        dispatchQueue.sync {
            publishers
                .once
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        onceExpectation.fulfill()
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.first?.title, "fake_title")
                    XCTAssertEqual(result.count, 1)

                    let newDocument = EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")
                    self.memoryStoreSpy.setResultStub = .success([newDocument])
                    self.remoteStoreSpy.setResultStub = .success([newDocument])
                    self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
                    self.manager
                        .set(newDocument, in: WriteContext(dataTarget: .local))
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &self.cancellables)
                    onceExpectation.fulfill()
                })
                .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                    } else {
                        XCTAssertEqual(result.first?.title, "updated_fake_title")
                        XCTAssertEqual(result.count, 1)
                    }
                    continuousCallCount += 1
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)
        }

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    // MARK: - Partial vs Complete Results

    func test_manager_should_send_new_truth_to_all_query_for_complete_results() {

        remoteStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let continuousExpectation1 = self.expectation(description: "continuous1")
        let continuousExpectation2 = self.expectation(description: "continuous2")
        let continuousExpectation3 = self.expectation(description: "continuous3")

        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let allQueryContext = ReadContext<EntitySpy>(dataSource: .local)

        let allQueryPublishers = manager.search(withQuery: .all, in: allQueryContext)

        dispatchQueue.sync {
            allQueryPublishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertTrue(result.isEmpty)
                        continuousExpectation1.fulfill()
                    } else if continuousCallCount == 1 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                        continuousExpectation2.fulfill()
                    } else {
                        XCTAssertEqual(result.first?.title, "another_fake_title")
                        XCTAssertEqual(result.count, 1)
                        continuousExpectation3.fulfill()
                    }
                    continuousCallCount += 1
                })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation1], timeout: 1)

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let firstContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        let firstUpdatePublishers = manager.search(withQuery: .all, in: firstContext)

        dispatchQueue.sync {
            firstUpdatePublishers
                .once
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation2], timeout: 1)

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil), title: "another_fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(43, nil), title: "another_fake_title")])

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        let secondUpdatePublishers = manager.search(withQuery: .all, in: secondContext)

        dispatchQueue.sync {
            secondUpdatePublishers
                .once
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation3], timeout: 1)
    }

    func test_manager_should_send_new_truth_to_all_query_for_contextual_results() {

        remoteStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let continuousExpectation1 = self.expectation(description: "continuous1")
        let continuousExpectation2 = self.expectation(description: "continuous2")
        let continuousExpectation3 = self.expectation(description: "continuous3")

        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let allQueryContext = ReadContext<EntitySpy>(dataSource: .local)

        let allQueryPublishers = manager.search(withQuery: .all, in: allQueryContext)

        dispatchQueue.sync {
            allQueryPublishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertTrue(result.isEmpty)
                        continuousExpectation1.fulfill()
                    } else if continuousCallCount == 1 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                        continuousExpectation2.fulfill()
                    } else {
                        let titles = result.map { $0.title }
                        XCTAssertTrue(titles.contains("fake_title"))
                        XCTAssertTrue(titles.contains("another_fake_title"))
                        XCTAssertEqual(result.count, 2)
                        continuousExpectation3.fulfill()
                    }
                    continuousCallCount += 1
                })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation1], timeout: 1)

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let firstContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.retainExtraLocalData)
            )
        )

        let firstUpdatePublishers = manager.search(withQuery: .all, in: firstContext)

        dispatchQueue.sync {
            firstUpdatePublishers
                .once
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation2], timeout: 1)

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil), title: "another_fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(43, nil), title: "another_fake_title")])

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.retainExtraLocalData)
            )
        )

        let secondUpdatePublishers = manager.search(withQuery: .all, in: secondContext)

        dispatchQueue.sync {
            secondUpdatePublishers
                .once
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation3], timeout: 1)
    }

    func test_manager_should_send_new_truth_to_all_query_for_paginated_results() {

        remoteStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let continuousExpectation1 = self.expectation(description: "continuous1")
        let continuousExpectation2 = self.expectation(description: "continuous2")
        let continuousExpectation3 = self.expectation(description: "continuous3")

        var continuousCallCount = 0
        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")

        let allQueryContext = ReadContext<EntitySpy>(dataSource: .local)

        let allQueryPublishers = manager.search(withQuery: .all, in: allQueryContext)

        dispatchQueue.sync {
            allQueryPublishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        Logger.log(.debug, "Did complete")
                    }
                }, receiveValue: { result in
                    if continuousCallCount == 0 {
                        XCTAssertTrue(result.isEmpty)
                        continuousExpectation1.fulfill()
                    } else if continuousCallCount == 1 {
                        XCTAssertEqual(result.first?.title, "fake_title")
                        XCTAssertEqual(result.count, 1)
                        continuousExpectation2.fulfill()
                    } else {
                        let titles = result.map { $0.title }
                        XCTAssertTrue(titles.contains("fake_title"))
                        XCTAssertTrue(titles.contains("another_fake_title"))
                        XCTAssertEqual(result.count, 2)
                        continuousExpectation3.fulfill()
                    }
                    continuousCallCount += 1
                })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation1], timeout: 1)

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil), title: "fake_title")])

        let firstContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(
                    method: .get,
                    path: .path("fake_entity"),
                    query: [("page", .value("1"))]
                ), resultPayload: .empty),
                persistenceStrategy: .persist(.retainExtraLocalData)
            )
        )

        let firstUpdatePublishers = manager.search(withQuery: .all, in: firstContext)

        dispatchQueue.sync {
            firstUpdatePublishers
                .once
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation2], timeout: 1)

        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil), title: "another_fake_title")]))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(43, nil), title: "another_fake_title")])

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(
                    method: .get,
                    path: .path("fake_entity"),
                    query: [("page", .value("1"))]
                ), resultPayload: .empty),
                persistenceStrategy: .persist(.retainExtraLocalData)
            )
        )

        let secondUpdatePublishers = manager.search(withQuery: .all, in: secondContext)

        dispatchQueue.sync {
            secondUpdatePublishers
                .once
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: &cancellables)
        }

        wait(for: [continuousExpectation3], timeout: 1)
    }

    // MARK: Deleting local records on search

    func test_manager_should_delete_non_matching_synced_local_records_for_complete_results() {

        let searchExpectation = self.expectation(description: "search")

        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(3, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(4, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(5, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.setResultStub = .success([])

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                searchExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [searchExpectation], timeout: 1)

        XCTAssertEqual(memoryStoreSpy.removeCallCount, 1)
        XCTAssertEqual(memoryStoreSpy.identifierRecords.count, 3)
        XCTAssertTrue(memoryStoreSpy.identifierRecords.contains(EntitySpyIdentifier(value: .remote(3, nil))))
        XCTAssertTrue(memoryStoreSpy.identifierRecords.contains(EntitySpyIdentifier(value: .remote(4, nil))))
        XCTAssertTrue(memoryStoreSpy.identifierRecords.contains(EntitySpyIdentifier(value: .remote(5, nil))))
    }

    func test_manager_should_not_delete_non_matching_out_of_sync_local_records_for_complete_results() {

        let searchExpectation = self.expectation(description: "search")

        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(3, nil), remoteSynchronizationState: .outOfSync),
            EntitySpy(idValue: .remote(4, nil), remoteSynchronizationState: .outOfSync),
            EntitySpy(idValue: .remote(5, nil), remoteSynchronizationState: .outOfSync)
        ]))
        memoryStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.setResultStub = .success([])

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                searchExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [searchExpectation], timeout: 1)

        XCTAssertEqual(memoryStoreSpy.removeCallCount, 0)
        XCTAssertEqual(memoryStoreSpy.identifierRecords.count, 0)
        XCTAssertTrue(memoryStoreSpy.identifierRecords.isEmpty)
    }

    func test_manager_should_not_delete_non_matching_synced_local_records_for_contextual_results() {

        let searchExpectation = self.expectation(description: "search")

        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(3, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(4, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(5, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.setResultStub = .success([])

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.retainExtraLocalData)
            )
        )

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                searchExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [searchExpectation], timeout: 1)

        XCTAssertEqual(memoryStoreSpy.removeCallCount, 0)
        XCTAssertEqual(memoryStoreSpy.identifierRecords.count, 0)
        XCTAssertTrue(memoryStoreSpy.identifierRecords.isEmpty)
    }

    func test_manager_should_not_delete_non_matching_synced_local_records_for_paginated_results() {

        let searchExpectation = self.expectation(description: "search")

        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(1, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(2, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(3, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(4, nil), remoteSynchronizationState: .synced),
            EntitySpy(idValue: .remote(5, nil), remoteSynchronizationState: .synced)
        ]))
        memoryStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.setResultStub = .success([])

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.retainExtraLocalData)
            )
        )

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                searchExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [searchExpectation], timeout: 1)

        XCTAssertEqual(memoryStoreSpy.removeCallCount, 0)
        XCTAssertEqual(memoryStoreSpy.identifierRecords.count, 0)
        XCTAssertTrue(memoryStoreSpy.identifierRecords.isEmpty)
    }

    // MARK: - Query Ordering

    func test_results_should_be_returned_in_query_order_ascending() {

        remoteStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let continuousExpectation1 = self.expectation(description: "continuous1")
        let continuousExpectation2 = self.expectation(description: "continuous2")
        var continuousCount = 0

        let query = Query<EntitySpy>(filter: .all,
                                     order: [.asc(by: .index(.title))])

        let firstContext = ReadContext<EntitySpy>(dataSource: .local)

        manager
            .search(withQuery: query, in: firstContext)
            .continuous
            .sink { result in
                if continuousCount == 0 {
                    continuousExpectation1.fulfill()
                } else {
                    guard result.count == 3 else {
                        XCTFail("Expected 3 entities")
                        return
                    }

                    XCTAssertEqual(result.array[0].title, "another_fake_title")
                    XCTAssertEqual(result.array[1].title, "fake_title")
                    XCTAssertEqual(result.array[2].title, "some_fake_title")

                    continuousExpectation2.fulfill()
                }
                continuousCount += 1
            }
            .store(in: &cancellables)

        wait(for: [continuousExpectation1], timeout: 1)

        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([])
        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(42, nil), title: "fake_title"),
            EntitySpy(idValue: .remote(43, nil), title: "another_fake_title"),
            EntitySpy(idValue: .remote(44, nil), title: "some_fake_title")
        ]))

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        manager.search(withQuery: .all, in: secondContext)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [continuousExpectation2], timeout: 1)
    }

    func test_results_should_be_returned_in_multiple_query_order_ascending_identifiers() {

        remoteStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let continuousExpectation1 = self.expectation(description: "continuous1")
        let continuousExpectation2 = self.expectation(description: "continuous2")
        var continuousCount = 0

        let query = Query<EntitySpy>(filter: .all,
                                     order: [.asc(by: .index(.title)),
                                             .asc(by: .identifier)])

        let firstContext = ReadContext<EntitySpy>(dataSource: .local)

        manager.search(withQuery: query, in: firstContext)
            .continuous
            .sink { result in
                if continuousCount == 0 {
                    continuousExpectation1.fulfill()
                } else {
                    guard result.count == 3 else {
                        XCTFail("Expected 3 entities")
                        return
                    }

                    XCTAssertEqual(result.array[0].identifier, EntitySpyIdentifier(value: .remote(43, nil)))
                    XCTAssertEqual(result.array[1].identifier, EntitySpyIdentifier(value: .remote(42, nil)))
                    XCTAssertEqual(result.array[2].identifier, EntitySpyIdentifier(value: .remote(44, nil)))

                    continuousExpectation2.fulfill()
                }
                continuousCount += 1
            }
            .store(in: &cancellables)

        wait(for: [continuousExpectation1], timeout: 1)

        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([])
        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(42, nil), title: "fake_title"),
            EntitySpy(idValue: .remote(43, nil), title: "another_fake_title"),
            EntitySpy(idValue: .remote(44, nil), title: "fake_title")
        ]))

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        manager.search(withQuery: .all, in: secondContext)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [continuousExpectation2], timeout: 1)
    }

    func test_results_should_be_returned_in_multiple_query_order_descending_identifiers() {

        remoteStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let continuousExpectation1 = self.expectation(description: "continuous1")
        let continuousExpectation2 = self.expectation(description: "continuous2")
        var continuousCount = 0

        let query = Query<EntitySpy>(filter: .all,
                                     order: [.asc(by: .index(.title)),
                                             .desc(by: .identifier)])

        let firstContext = ReadContext<EntitySpy>(dataSource: .local)

        manager.search(withQuery: query, in: firstContext)
            .continuous
            .sink { result in
                if continuousCount == 0 {
                    continuousExpectation1.fulfill()
                } else {
                    guard result.count == 3 else {
                        XCTFail("Expected 3 entities")
                        return
                    }

                    XCTAssertEqual(result.array[0].identifier, EntitySpyIdentifier(value: .remote(43, nil)))
                    XCTAssertEqual(result.array[1].identifier, EntitySpyIdentifier(value: .remote(44, nil)))
                    XCTAssertEqual(result.array[2].identifier, EntitySpyIdentifier(value: .remote(42, nil)))

                    continuousExpectation2.fulfill()
                }
                continuousCount += 1
            }
            .store(in: &cancellables)

        wait(for: [continuousExpectation1], timeout: 1)

        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([])
        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(42, nil), title: "fake_title"),
            EntitySpy(idValue: .remote(43, nil), title: "another_fake_title"),
            EntitySpy(idValue: .remote(44, nil), title: "fake_title")
        ]))

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        manager.search(withQuery: .all, in: secondContext)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &cancellables)

        wait(for: [continuousExpectation2], timeout: 1)
    }

    func test_results_should_be_returned_in_query_order_natural() {

        memoryStoreSpy.searchResultStub = .success(.entities([]))
        memoryStoreSpy.setResultStub = .success([])
        remoteStoreSpy.searchResultStub = .success(.entities([
            EntitySpy(idValue: .remote(43, nil), title: "fake_title"),
            EntitySpy(idValue: .remote(42, nil), title: "another_fake_title"),
            EntitySpy(idValue: .remote(44, nil), title: "some_fake_title")
        ]))

        let secondContext = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            )
        )

        let expectation = self.expectation(description: "order")

        manager
            .search(withQuery: .all, in: secondContext)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertEqual(result.map { $0.title }, [
                    "fake_title",
                    "another_fake_title",
                    "some_fake_title"
                ])
                expectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1)
    }

    // MARK: - Disposing

    func test_search_should_release_continuous_provider_as_soon_as_the_observer_is_disposed() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        memoryStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
        remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.isInverted = true

        let context = ReadContext<EntitySpy>(
            dataSource: .localThen(.remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ))
        )

        manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .continuous
            .sink { _ in
                continuousExpectation.fulfill()
            }
            .store(in: &cancellables)

        cancellables.forEach { $0.cancel() }

        wait(for: [continuousExpectation], timeout: 1)
    }

    func test_search_should_release_once_provider_as_soon_as_the_observer_is_disposed() {

        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "fake_title")]))
        remoteStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(42, nil), title: "updated_fake_title")]))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        memoryStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
        remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.isInverted = true

        let context = ReadContext<EntitySpy>(
            dataSource: .localThen(.remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ))
        )

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        cancellables.forEach { $0.cancel() }

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_should_release_once_provider_as_soon_as_the_observer_is_disposed() {

        memoryStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil), title: "fake_title")))
        remoteStoreSpy.getResultStub = .success(QueryResult(from: EntitySpy(idValue: .remote(42, nil), title: "fake_title")))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        memoryStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
        remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.isInverted = true

        let context = ReadContext<EntitySpy>(
            dataSource: .localThen(.remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ))
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        cancellables.forEach { $0.cancel() }

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_set_should_release_once_provider_as_soon_as_the_observer_is_disposed() {

        let entity = EntitySpy(idValue: .remote(42, nil), title: "fake_title")
        memoryStoreSpy.setResultStub = .success([entity])
        remoteStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        memoryStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue
        remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.isInverted = true

        manager
            .set(entity, in: WriteContext(dataTarget: .local))
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        cancellables.forEach { $0.cancel() }

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: - Observer Ordering

    func test_continuous_observer_should_receive_all_updates_in_order() {
        let count = 400

        let expectedResults = (0..<count).map { index in
            (0..<index).map { EntitySpy(idValue: .remote($0, nil), title: "title_\($0)") }
        }

        let memoryStore = InMemoryStore<EntitySpy>()
        manager = CoreManager(stores: [memoryStore.storing]).managing()

        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = count
        var continuousCallCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .local)

        manager
            .search(withQuery: .all, in: context)
            .continuous
            .sink { result in
                guard continuousCallCount < count else {
                    XCTFail("received too many responses")
                    return
                }
                XCTAssertEqual(result.any, expectedResults[continuousCallCount].any)
                continuousCallCount += 1
                continuousExpectation.fulfill()
            }
            .store(in: &cancellables)

        let entities = (0..<count).map { EntitySpy(idValue: .remote($0, nil), title: "title_\($0)") }

        entities.forEach { entity in
            manager
                .set(entity, in: WriteContext(dataTarget: .local))
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("\(error)")
                    case .finished:
                        break
                    }
                }, receiveValue: { _ in })
                .store(in: &cancellables)

        }

        wait(for: [continuousExpectation], timeout: 60)
    }

    // MARK: - Metadata Root Filtering

    private var stubMetadata: Metadata<EntitySpy> {
        let topLevelDocumentMetadata: [EntityMetadata?] = [
            EntitySpyMetadata(remoteID: 2),
            EntitySpyMetadata(remoteID: 3)
        ]

        let endpointResultMetadata = EndpointResultMetadata(endpoint: nil, entity: topLevelDocumentMetadata.any)
        return Metadata<EntitySpy>(endpointResultMetadata)
    }

    // MARK: - Request Token Tests

    // MARK: GET

    func test_get_request_returns_request_token_and_metadata_for_remote_only_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.getResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_request_returns_request_token_and_metadata_for_prefer_remote_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.getResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))
        memoryStoreSpy.getResultStub = .success(QueryResult<EntitySpy>(from: entity))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_request_returns_request_token_and_metadata_for_prefer_local_strategy_and_local_store_fails() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.getResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))
        memoryStoreSpy.getResultStub = .failure(.invalidCoreDataEntity)
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: SEARCH

    func test_search_request_returns_request_token_and_metadata_for_remote_only_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_request_returns_request_token_and_metadata_for_prefer_remote_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))
        memoryStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity))
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_request_returns_request_token_and_metadata_for_prefer_local_strategy_and_local_store_fails() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))
        memoryStoreSpy.searchResultStub = .failure(.invalidCoreDataEntity)
        memoryStoreSpy.setResultStub = .success([EntitySpy(idValue: .remote(42, nil))])

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .localThen(.remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        )))

        manager
            .search(withQuery: .all, in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: All Entities Convenience

    func test_all_entities_convenience_request_returns_request_token_and_metadata_for_remote_only_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .all(in: context)
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: Entities Convenience

    func test_entities_convenience_request_returns_request_token_and_metadata_for_remote_only_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .get(byIDs: [EntitySpyIdentifier(value: .remote(42, nil))], in: context)
            .once
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: First With Metadata Convenience

    func test_first_with_metadata_convenience_request_returns_request_token_and_metadata_for_remote_only_strategy() {

        let entity = EntitySpy(idValue: .remote(42, nil))

        remoteStoreSpy.searchResultStub = .success(QueryResult<EntitySpy>(from: entity, metadata: stubMetadata))

        let onceExpectation = self.expectation(description: "once")

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .doNotPersist
        ))

        manager
            .firstWithMetadata(in: context)
            .sink(receiveCompletion: { _ in }, receiveValue: { result in
                XCTAssertNotNil(result.metadata)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: Test Updates For Extras Changes

    func test_manager_should_not_send_entity_update_to_provider_when_lazy_value_changes_from_unrequested_to_unrequested() {

        let entity = EntitySpy(idValue: .remote(42, nil), lazy: .unrequested)
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")

        var continuousCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.lazy, .unrequested)
                XCTAssertEqual(result.count, 1)

                let updatedEntity = EntitySpy(idValue: .remote(42, nil), lazy: .unrequested)
                let mergedEntity = entity.merging(updatedEntity)
                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: mergedEntity))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
            }, receiveValue: { result in
                if continuousCount == 0 {
                    XCTAssertEqual(result.first?.lazy, .unrequested)
                    XCTAssertEqual(result.count, 1)
                    continuousExpectation.fulfill()
                } else {
                    XCTFail("Received too many updates")
                }
                continuousCount += 1
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)

        let additionalSignalExpectation = self.expectation(description: "additional")

        DispatchQueue(label: "test").asyncAfter(deadline: .now() + .milliseconds(100)) {
            additionalSignalExpectation.fulfill()
        }

        wait(for: [additionalSignalExpectation], timeout: 1.0)
    }

    func test_manager_should_not_send_entity_update_to_provider_when_lazy_value_changes_from_requested_to_unrequested() {

        let entity = EntitySpy(idValue: .remote(42, nil), lazy: .requested(6))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")

        var continuousCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.lazy, .requested(6))
                XCTAssertEqual(result.count, 1)

                let updatedEntity = EntitySpy(idValue: .remote(42, nil), lazy: .unrequested)
                let mergedEntity = entity.merging(updatedEntity)
                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: mergedEntity))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
            }, receiveValue: { result in
                if continuousCount == 0 {
                    XCTAssertEqual(result.first?.lazy, .requested(6))
                    XCTAssertEqual(result.count, 1)
                    continuousExpectation.fulfill()
                } else {
                    XCTFail("Received too many updates")
                }
                continuousCount += 1
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)

        let additionalSignalExpectation = self.expectation(description: "additional")

        DispatchQueue(label: "test").asyncAfter(deadline: .now() + .milliseconds(100)) {
            additionalSignalExpectation.fulfill()
        }

        wait(for: [additionalSignalExpectation], timeout: 1.0)
    }

    func test_manager_should_not_send_entity_update_to_provider_when_lazy_value_changes_from_requested_to_same_requested_value() {

        let entity = EntitySpy(idValue: .remote(42, nil), lazy: .requested(6))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")

        var continuousCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.lazy, .requested(6))
                XCTAssertEqual(result.count, 1)

                let updatedEntity = EntitySpy(idValue: .remote(42, nil), lazy: .requested(6))
                let mergedEntity = entity.merging(updatedEntity)
                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: mergedEntity))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
            }, receiveValue: { result in
                if continuousCount == 0 {
                    XCTAssertEqual(result.first?.lazy, .requested(6))
                    XCTAssertEqual(result.count, 1)
                    continuousExpectation.fulfill()
                } else {
                    XCTFail("Received too many updates")
                }
                continuousCount += 1
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)

        let additionalSignalExpectation = self.expectation(description: "additional")

        DispatchQueue(label: "test").asyncAfter(deadline: .now() + .milliseconds(100)) {
            additionalSignalExpectation.fulfill()
        }

        wait(for: [additionalSignalExpectation], timeout: 1.0)
    }

    func test_manager_should_send_entity_update_to_provider_when_lazy_value_changes_from_unrequested_to_requested() {

        let entity = EntitySpy(idValue: .remote(42, nil), lazy: .unrequested)
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2

        var continuousCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.lazy, .unrequested)
                XCTAssertEqual(result.count, 1)

                let updatedEntity = EntitySpy(idValue: .remote(42, nil), lazy: .requested(5))
                let mergedEntity = entity.merging(updatedEntity)
                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: mergedEntity))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
            }, receiveValue: { result in
                if continuousCount == 0 {
                    XCTAssertEqual(result.first?.lazy, .unrequested)
                    XCTAssertEqual(result.count, 1)
                } else {
                    XCTAssertEqual(result.first?.lazy, .requested(5))
                    XCTAssertEqual(result.count, 1)
                }
                continuousCount += 1
                continuousExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_manager_should_send_entity_update_to_provider_when_lazy_value_changes_from_requested_to_new_requested_value() {

        let entity = EntitySpy(idValue: .remote(42, nil), lazy: .requested(7))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2
        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 2

        var continuousCount = 0

        let context = ReadContext<EntitySpy>(dataSource: .remote(
            endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
            persistenceStrategy: .persist(.discardExtraLocalData)
        ))

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.first?.lazy, .requested(7))
                XCTAssertEqual(result.count, 1)

                let updatedEntity = EntitySpy(idValue: .remote(42, nil), lazy: .requested(99))
                let mergedEntity = entity.merging(updatedEntity)
                self.remoteStoreSpy.getResultStub = .success(QueryResult(from: mergedEntity))
                let getContext = ReadContext<EntitySpy>(dataSource: .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                ))
                self.manager
                    .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: getContext)
                    .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                    .store(in: &self.cancellables)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
            }, receiveValue: { result in
                if continuousCount == 0 {
                    XCTAssertEqual(result.first?.lazy, .requested(7))
                    XCTAssertEqual(result.count, 1)
                } else {
                    XCTAssertEqual(result.first?.lazy, .requested(99))
                    XCTAssertEqual(result.count, 1)
                }
                continuousCount += 1
                continuousExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    // MARK: - UserAccessLevels - Requests

    func test_get_returns_remote_data_for_remote_access_level() {
        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertNotNil(result.entity)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_returns_local_data_for_local_access_level() {
        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        let context = ReadContext<EntitySpy>(
            dataSource: .remoteOrLocal(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertNotNil(result.entity)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_returns_error_for_no_access_level() {
        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_returns_remote_data_for_remote_access_level() {
        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        XCTFail("Unexpected completion.")
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.count, 1)
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_search_returns_local_data_for_local_access_level() {
        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let continuousExpectation = self.expectation(description: "continuous")
        continuousExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        let context = ReadContext<EntitySpy>(
            dataSource: .remoteOrLocal(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 0)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 0)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

            publishers
                .continuous
                .sink(receiveCompletion: { completion in
                    switch completion {
                    case .failure(let error):
                        XCTFail("Unexpected error: \(error)")
                    case .finished:
                        XCTFail("Unexpected completion.")
                    }
                }, receiveValue: { result in
                    XCTAssertEqual(result.count, 1)
                    continuousExpectation.fulfill()
                })
                .store(in: &cancellables)

        wait(for: [onceExpectation, continuousExpectation], timeout: 1)
    }

    func test_search_returns_failure_for_once_and_no_data_for_continuous_for_no_access_level() {
        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        let context = ReadContext<EntitySpy>(
            dataSource: .remote(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        let publishers = manager.search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)

        publishers
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    DispatchQueue.global().async {
                        onceExpectation.fulfill()
                    }
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        publishers
            .continuous
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_set_returns_remote_response_for_remote_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()

        manager
            .set(
                entity,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(self.remoteStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_set_returns_local_response_for_local_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        manager
            .set(
                entity,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(self.remoteStoreSpy.entityRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_set_returns_failure_for_no_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        manager
            .set(
                entity,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_set_array_returns_remote_response_for_remote_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()

        manager
            .set(
                [entity],
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation .fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(self.remoteStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                onceExpectation .fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_set_array_returns_local_response_for_local_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        manager
            .set(
                [entity],
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { result in
                XCTAssertEqual(self.remoteStoreSpy.entityRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.entityRecords.first?.identifier.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_set_array_returns_failure_for_no_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        manager
            .set(
                [entity],
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_returns_remote_response_for_remote_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()

        manager
            .remove(
                atID: entity.identifier,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { _ in
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_returns_local_response_for_local_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        manager
            .remove(
                atID: entity.identifier,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { _ in
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_returns_failure_for_no_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        manager
            .remove(
                atID: entity.identifier,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_array_returns_remote_response_for_remote_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()

        manager
            .remove(
                [entity.identifier],
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { _ in
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_array_returns_local_response_for_local_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        manager
            .remove(
                [entity.identifier],
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { _ in
                XCTAssertEqual(self.remoteStoreSpy.identifierRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.count, 1)
                XCTAssertEqual(self.memoryStoreSpy.identifierRecords.first?.value.remoteValue, 42)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_array_returns_failure_for_no_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        manager
            .remove(
                [entity.identifier],
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_all_returns_remote_response_for_remote_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeAllResultStub = .success([entity.identifier])
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.removeAllResultStub = .success([entity.identifier])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()

        manager
            .removeAll(
                withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))),
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { _ in
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 1)
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 2)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.last?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_all_returns_local_response_for_local_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeAllResultStub = .success([entity.identifier])
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.removeAllResultStub = .success([entity.identifier])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .localAccess

        manager
            .removeAll(
                withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))),
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    break
                }
                onceExpectation.fulfill()
            }, receiveValue: { _ in
                XCTAssertEqual(self.remoteStoreSpy.queryRecords.count, 0)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.count, 2)
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.first?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                XCTAssertEqual(self.memoryStoreSpy.queryRecords.last?.filter, .identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil))))
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_user_access_validation_remove_all_returns_failure_for_no_access_level() {

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeAllResultStub = .success([entity.identifier])
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.removeAllResultStub = .success([entity.identifier])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = .noAccess

        manager
            .removeAll(
                withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))),
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    // MARK: - UserAccessLevels - Requests

    func performGetForAccessLevelChange(from request: UserAccess, to response: UserAccess) {
        let remoteStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        remoteStoreSpy.levelStub = .remote
        let memoryStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        memoryStoreSpy.levelStub = .memory

        manager = CoreManager(stores: [remoteStoreSpy.storing, memoryStoreSpy.storing]).managing()

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.getResultStub = .success(QueryResult(from: entity))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = request
        remoteStoreSpy.userAccessSpy = validatorSpy
        remoteStoreSpy.userAccessAfterStoreResponse = response
        memoryStoreSpy.userAccessSpy = validatorSpy
        memoryStoreSpy.userAccessAfterStoreResponse = response

        let context = ReadContext<EntitySpy>(
            dataSource: .remoteOrLocal(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completed")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected success")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_returns_failure_for_change_from_remote_access_to_local_access() {
        performGetForAccessLevelChange(from: .remoteAccess, to: .localAccess)
    }

    func test_get_returns_failure_for_change_from_remote_access_to_no_access() {
        performGetForAccessLevelChange(from: .remoteAccess, to: .noAccess)
    }

    func test_get_returns_failure_for_change_from_local_access_to_remote_access() {
        performGetForAccessLevelChange(from: .localAccess, to: .remoteAccess)
    }

    func test_get_returns_failure_for_change_from_local_access_to_no_access() {
        performGetForAccessLevelChange(from: .localAccess, to: .noAccess)
    }

    func performSearchForAccessLevelChange(from request: UserAccess, to response: UserAccess) {
        let remoteStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        remoteStoreSpy.levelStub = .remote
        let memoryStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        memoryStoreSpy.levelStub = .memory
        manager = CoreManager(stores: [remoteStoreSpy.storing, memoryStoreSpy.storing]).managing()

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = request
        remoteStoreSpy.userAccessSpy = validatorSpy
        remoteStoreSpy.userAccessAfterStoreResponse = response
        memoryStoreSpy.userAccessSpy = validatorSpy
        memoryStoreSpy.userAccessAfterStoreResponse = response

        let context = ReadContext<EntitySpy>(
            dataSource: .remoteOrLocal(
                endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                persistenceStrategy: .persist(.discardExtraLocalData)
            ),
            accessValidator: validatorSpy
        )

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    DispatchQueue.global().async {
                        onceExpectation.fulfill()
                    }
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_returns_failure_for_change_from_remote_access_to_local_access() {
        performSearchForAccessLevelChange(from: .remoteAccess, to: .localAccess)
    }

    func test_search_returns_failure_for_change_from_remote_access_to_no_access() {
        performSearchForAccessLevelChange(from: .remoteAccess, to: .noAccess)
    }

    func test_search_returns_failure_for_change_from_local_access_to_remote_access() {
        performSearchForAccessLevelChange(from: .localAccess, to: .remoteAccess)
    }

    func test_search_returns_failure_for_change_from_local_access_to_no_access() {
        performSearchForAccessLevelChange(from: .localAccess, to: .noAccess)
    }

    func performSetForAccessLevelChange(from request: UserAccess, to response: UserAccess) {
        let remoteStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        remoteStoreSpy.levelStub = .remote
        let memoryStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        memoryStoreSpy.levelStub = .memory
        manager = CoreManager(stores: [remoteStoreSpy.storing, memoryStoreSpy.storing]).managing()

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.setResultStub = .success([entity])
        memoryStoreSpy.setResultStub = .success([entity])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = request
        remoteStoreSpy.userAccessSpy = validatorSpy
        remoteStoreSpy.userAccessAfterStoreResponse = response
        memoryStoreSpy.userAccessSpy = validatorSpy
        memoryStoreSpy.userAccessAfterStoreResponse = response

        manager
            .set(
                entity,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_set_returns_failure_for_change_from_remote_access_to_local_access() {
        performSetForAccessLevelChange(from: .remoteAccess, to: .localAccess)
    }

    func test_set_returns_failure_for_change_from_remote_access_to_no_access() {
        performSetForAccessLevelChange(from: .remoteAccess, to: .noAccess)
    }

    func test_set_returns_failure_for_change_from_local_access_to_remote_access() {
        performSetForAccessLevelChange(from: .localAccess, to: .remoteAccess)
    }

    func test_set_returns_failure_for_change_from_local_access_to_no_access() {
        performSetForAccessLevelChange(from: .localAccess, to: .noAccess)
    }

    func performRemoveForAccessLevelChange(from request: UserAccess, to response: UserAccess) {
        let remoteStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        remoteStoreSpy.levelStub = .remote
        let memoryStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        memoryStoreSpy.levelStub = .memory
        manager = CoreManager(stores: [remoteStoreSpy.storing, memoryStoreSpy.storing]).managing()

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeResultStub = .success(())
        memoryStoreSpy.removeResultStub = .success(())

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = request
        remoteStoreSpy.userAccessSpy = validatorSpy
        remoteStoreSpy.userAccessAfterStoreResponse = response
        memoryStoreSpy.userAccessSpy = validatorSpy
        memoryStoreSpy.userAccessAfterStoreResponse = response

        manager
            .remove(
                atID: entity.identifier,
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_remove_returns_failure_for_change_from_remote_access_to_local_access() {
        performRemoveForAccessLevelChange(from: .remoteAccess, to: .localAccess)
    }

    func test_remove_returns_failure_for_change_from_remote_access_to_no_access() {
        performRemoveForAccessLevelChange(from: .remoteAccess, to: .noAccess)
    }

    func test_remove_returns_failure_for_change_from_local_access_to_remote_access() {
        performRemoveForAccessLevelChange(from: .localAccess, to: .remoteAccess)
    }

    func test_remove_returns_failure_for_change_from_local_access_to_no_access() {
        performRemoveForAccessLevelChange(from: .localAccess, to: .noAccess)
    }

    func performRemoveAllForAccessLevelChange(from request: UserAccess, to response: UserAccess) {
        let remoteStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        remoteStoreSpy.levelStub = .remote
        let memoryStoreSpy = UserAccessInvalidatingStoreSpy<EntitySpy>()
        memoryStoreSpy.levelStub = .memory
        manager = CoreManager(stores: [remoteStoreSpy.storing, memoryStoreSpy.storing]).managing()

        let entity = EntitySpy(idValue: .remote(42, nil))
        remoteStoreSpy.removeAllResultStub = .success([entity.identifier])
        memoryStoreSpy.searchResultStub = .success(.entities([entity]))
        memoryStoreSpy.removeAllResultStub = .success([entity.identifier])

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 1

        let validatorSpy = UserAccessValidatorSpy()
        validatorSpy.stub = request
        remoteStoreSpy.userAccessSpy = validatorSpy
        remoteStoreSpy.userAccessAfterStoreResponse = response
        memoryStoreSpy.userAccessSpy = validatorSpy
        memoryStoreSpy.userAccessAfterStoreResponse = response

        manager
            .removeAll(
                withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))),
                in: WriteContext(dataTarget: .localAndRemote(endpoint: .derivedFromEntityType), accessValidator: validatorSpy)
            )
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTAssertEqual(error, .userAccessInvalid)
                    onceExpectation.fulfill()
                case .finished:
                    XCTFail("Unexpected completion.")
                }
            }, receiveValue: { _ in
                XCTFail("Unexpected value.")
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_remove_all_returns_failure_for_change_from_remote_access_to_local_access() {
        performRemoveAllForAccessLevelChange(from: .remoteAccess, to: .localAccess)
    }

    func test_remove_all_returns_failure_for_change_from_remote_access_to_no_access() {
        performRemoveAllForAccessLevelChange(from: .remoteAccess, to: .noAccess)
    }

    func test_remove_all_returns_failure_for_change_from_local_access_to_remote_access() {
        performRemoveAllForAccessLevelChange(from: .localAccess, to: .remoteAccess)
    }

    func test_remove_all_returns_failure_for_change_from_local_access_to_no_access() {
        performRemoveAllForAccessLevelChange(from: .localAccess, to: .noAccess)
    }

    // MARK: - Fall back to local errors
    // MARK: get: local --> remote

    func test_get_local_or_remote_returns_nil_result_if_local_result_missing_and_receiving_internet_connection_error() {
        remoteStoreSpy.getResultStub = .failure(.api(.network(.networkConnectionFailure(.networkConnectionLost))))
        memoryStoreSpy.getResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localOr(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_local_then_remote_returns_nil_result_if_local_result_missing_and_receiving_internet_connection_error() {
        remoteStoreSpy.getResultStub = .failure(.api(.network(.networkConnectionFailure(.networkConnectionLost))))
        memoryStoreSpy.getResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localThen(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_local_or_remote_returns_nil_result_if_local_result_missing_and_receiving_empty_response_error() {
        remoteStoreSpy.getResultStub = .failure(.emptyResponse)
        memoryStoreSpy.getResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localOr(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_get_local_then_remote_returns_nil_result_if_local_result_missing_and_receiving_empty_response_error() {
        remoteStoreSpy.getResultStub = .failure(.emptyResponse)
        memoryStoreSpy.getResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localThen(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .get(byID: EntitySpyIdentifier(value: .remote(42, nil)), in: context)
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }
    // MARK: search: local --> remote

    func test_search_local_or_remote_returns_nil_result_if_local_result_missing_and_receiving_internet_connection_error() {
        remoteStoreSpy.searchResultStub = .failure(.api(.network(.networkConnectionFailure(.networkConnectionLost))))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localOr(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .search(
                withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))),
                in: context
            )
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_then_remote_returns_nil_result_if_local_result_missing_and_receiving_internet_connection_error() {
        remoteStoreSpy.searchResultStub = .failure(.api(.network(.networkConnectionFailure(.networkConnectionLost))))
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localThen(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .search(
                withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))),
                in: context
            )
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_or_remote_returns_partial_local_result_when_receiving_internet_connection_error() {
        remoteStoreSpy.searchResultStub = .failure(.api(.network(.networkConnectionFailure(.networkConnectionLost))))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil))]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localOr(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(result.first?.identifier, EntitySpyIdentifier(value: .remote(43, nil)))
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_then_remote_returns_partial_local_result_when_receiving_internet_connection_error() {
        remoteStoreSpy.searchResultStub = .failure(.api(.network(.networkConnectionFailure(.networkConnectionLost))))
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil))]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localThen(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(result.first?.identifier, EntitySpyIdentifier(value: .remote(43, nil)))
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_or_remote_returns_nil_result_if_local_result_missing_and_receiving_empty_response_error() {
        remoteStoreSpy.searchResultStub = .failure(.emptyResponse)
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localOr(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_then_remote_returns_nil_result_if_local_result_missing_and_receiving_empty_response_error() {
        remoteStoreSpy.searchResultStub = .failure(.emptyResponse)
        memoryStoreSpy.searchResultStub = .success(.entities([]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localThen(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        manager
            .search(withQuery: .filter(.identifier == .identifier(EntitySpyIdentifier(value: .remote(42, nil)))), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertTrue(result.isEmpty)
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_or_remote_returns_partial_local_result_when_receiving_empty_response_error() {
        remoteStoreSpy.searchResultStub = .failure(.emptyResponse)
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil))]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localOr(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(result.first?.identifier, EntitySpyIdentifier(value: .remote(43, nil)))
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }

    func test_search_local_then_remote_returns_partial_local_result_when_receiving_empty_response_error() {
        remoteStoreSpy.searchResultStub = .failure(.emptyResponse)
        memoryStoreSpy.searchResultStub = .success(.entities([EntitySpy(idValue: .remote(43, nil))]))

        let dispatchQueue = DispatchQueue(label: "CoreManagerTestsQueue")
        self.remoteStoreSpy.stubAsynchronousCompletionQueue = dispatchQueue

        let onceExpectation = self.expectation(description: "once")
        onceExpectation.expectedFulfillmentCount = 2

        let context = ReadContext<EntitySpy>(dataSource:
            .localThen(
                .remote(
                    endpoint: .request(APIRequestConfig(method: .get, path: .path("fake_entity/42")), resultPayload: .empty),
                    persistenceStrategy: .persist(.discardExtraLocalData)
                )
            )
        )

        let expectedIdentifiers = [EntitySpyIdentifier(value: .remote(42, nil)), EntitySpyIdentifier(value: .remote(43, nil))]
        manager
            .search(withQuery: .filter(.identifier >> expectedIdentifiers), in: context)
            .once
            .sink(receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    XCTFail("Unexpected error: \(error)")
                case .finished:
                    onceExpectation.fulfill()
                }
            }, receiveValue: { result in
                XCTAssertEqual(result.count, 1)
                XCTAssertEqual(result.first?.identifier, EntitySpyIdentifier(value: .remote(43, nil)))
                onceExpectation.fulfill()
            })
            .store(in: &cancellables)

        wait(for: [onceExpectation], timeout: 1)
    }
}

// MARK: - UserAccessValidatorSpy Helper

private final class UserAccessInvalidatingStoreSpy<E: Entity>: StoreSpy<E> {

    var userAccessAfterStoreResponse: UserAccess = .remoteAccess
    var userAccessSpy: UserAccessValidatorSpy?

    override func get(withQuery query: Query<E>, in context: ReadContext<E>, completion: @escaping (Result<QueryResult<E>, StoreError>) -> Void) {
        userAccessSpy?.stub = userAccessAfterStoreResponse
        super.get(withQuery: query, in: context, completion: completion)
    }

    override func search(withQuery query: Query<E>, in context: ReadContext<E>, completion: @escaping (Result<QueryResult<E>, StoreError>) -> Void) {
        userAccessSpy?.stub = userAccessAfterStoreResponse
        super.search(withQuery: query, in: context, completion: completion)
    }

    override func set<S>(_ entities: S, in context: WriteContext<E>, completion: @escaping (Result<AnySequence<E>, StoreError>?) -> Void) where S: Sequence, S.Element == E {
        userAccessSpy?.stub = userAccessAfterStoreResponse
        super.set(entities, in: context, completion: completion)
    }

    override func removeAll(withQuery query: Query<E>, in context: WriteContext<E>, completion: @escaping (Result<AnySequence<E.Identifier>, StoreError>?) -> Void) {
        userAccessSpy?.stub = userAccessAfterStoreResponse
        super.removeAll(withQuery: query, in: context, completion: completion)
    }

    override func remove<S>(_ identifiers: S, in context: WriteContext<E>, completion: @escaping (Result<Void, StoreError>?) -> Void) where S: Sequence, S.Element == E.Identifier {
        userAccessSpy?.stub = userAccessAfterStoreResponse
        super.remove(identifiers, in: context, completion: completion)
    }
}
