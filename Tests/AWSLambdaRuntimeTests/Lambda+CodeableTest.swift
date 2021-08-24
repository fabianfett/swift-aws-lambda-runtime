//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

@testable import AWSLambdaRuntime
@testable import AWSLambdaRuntimeCore
import Logging
import NIOCore
import NIOFoundationCompat
import NIOPosix
import XCTest

class CodableLambdaTest: XCTestCase {
    var eventLoopGroup: EventLoopGroup!
    let allocator = ByteBufferAllocator()

    override func setUp() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    override func tearDown() {
        XCTAssertNoThrow(try self.eventLoopGroup.syncShutdownGracefully())
    }

    func testCodableVoidEventLoopFutureHandler() {
        let request = Request(requestId: UUID().uuidString)
        var inputBuffer: ByteBuffer?
        var outputBuffer: ByteBuffer?

        struct Handler: EventLoopLambdaHandler {
            typealias In = Request
            typealias Out = Void

            let expected: Request

            func handle(context: Lambda.Context, event: Request) -> EventLoopFuture<Void> {
                XCTAssertEqual(event, self.expected)
                return context.eventLoop.makeSucceededVoidFuture()
            }
        }

        let handler = Handler(expected: request)

        XCTAssertNoThrow(inputBuffer = try JSONEncoder().encode(request, using: self.allocator))
        XCTAssertNoThrow(outputBuffer = try handler.handle(context: self.newContext(), event: XCTUnwrap(inputBuffer)).wait())
        XCTAssertNil(outputBuffer)
    }

    func testCodableEventLoopFutureHandler() {
        let request = Request(requestId: UUID().uuidString)
        var inputBuffer: ByteBuffer?
        var outputBuffer: ByteBuffer?
        var response: Response?

        struct Handler: EventLoopLambdaHandler {
            typealias In = Request
            typealias Out = Response

            let expected: Request

            func handle(context: Lambda.Context, event: Request) -> EventLoopFuture<Response> {
                XCTAssertEqual(event, self.expected)
                return context.eventLoop.makeSucceededFuture(Response(requestId: event.requestId))
            }
        }

        let handler = Handler(expected: request)

        XCTAssertNoThrow(inputBuffer = try JSONEncoder().encode(request, using: self.allocator))
        XCTAssertNoThrow(outputBuffer = try handler.handle(context: self.newContext(), event: XCTUnwrap(inputBuffer)).wait())
        XCTAssertNoThrow(response = try JSONDecoder().decode(Response.self, from: XCTUnwrap(outputBuffer)))
        XCTAssertEqual(response?.requestId, request.requestId)
    }

    #if swift(>=5.5)
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func testCodableVoidHandler() {
        struct Handler: LambdaHandler {
            typealias In = Request
            typealias Out = Void

            var expected: Request?

            init(context: Lambda.InitializationContext) async throws {}

            func handle(event: Request, context: Lambda.Context) async throws {
                XCTAssertEqual(event, self.expected)
            }
        }

        XCTAsyncTest {
            let request = Request(requestId: UUID().uuidString)
            var inputBuffer: ByteBuffer?
            var outputBuffer: ByteBuffer?

            var handler = try await Handler(context: self.newInitContext())
            handler.expected = request

            XCTAssertNoThrow(inputBuffer = try JSONEncoder().encode(request, using: self.allocator))
            XCTAssertNoThrow(outputBuffer = try handler.handle(context: self.newContext(), event: XCTUnwrap(inputBuffer)).wait())
            XCTAssertNil(outputBuffer)
        }
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func testCodableHandler() {
        struct Handler: LambdaHandler {
            typealias In = Request
            typealias Out = Response

            var expected: Request?

            init(context: Lambda.InitializationContext) async throws {}

            func handle(event: Request, context: Lambda.Context) async throws -> Response {
                XCTAssertEqual(event, self.expected)
                return Response(requestId: event.requestId)
            }
        }

        XCTAsyncTest {
            let request = Request(requestId: UUID().uuidString)
            var response: Response?
            var inputBuffer: ByteBuffer?
            var outputBuffer: ByteBuffer?

            var handler = try await Handler(context: self.newInitContext())
            handler.expected = request

            XCTAssertNoThrow(inputBuffer = try JSONEncoder().encode(request, using: self.allocator))
            XCTAssertNoThrow(outputBuffer = try handler.handle(context: self.newContext(), event: XCTUnwrap(inputBuffer)).wait())
            XCTAssertNoThrow(response = try JSONDecoder().decode(Response.self, from: XCTUnwrap(outputBuffer)))
            XCTAssertEqual(response?.requestId, request.requestId)
        }
    }
    #endif

    // convencience method
    func newContext() -> Lambda.Context {
        Lambda.Context(requestID: UUID().uuidString,
                       traceID: "abc123",
                       invokedFunctionARN: "aws:arn:",
                       deadline: .now() + .seconds(3),
                       cognitoIdentity: nil,
                       clientContext: nil,
                       logger: Logger(label: "test"),
                       invocationCount: 0,
                       eventLoop: self.eventLoopGroup.next(),
                       allocator: ByteBufferAllocator())
    }

    func newInitContext() -> Lambda.InitializationContext {
        Lambda.InitializationContext(logger: Logger(label: "test"),
                                     eventLoop: self.eventLoopGroup.next(),
                                     allocator: ByteBufferAllocator())
    }
}

private struct Request: Codable, Equatable {
    let requestId: String
    init(requestId: String) {
        self.requestId = requestId
    }
}

private struct Response: Codable, Equatable {
    let requestId: String
    init(requestId: String) {
        self.requestId = requestId
    }
}

#if swift(>=5.5)
// NOTE: workaround until we have async test support on linux
//         https://github.com/apple/swift-corelibs-xctest/pull/326
extension XCTestCase {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func XCTAsyncTest(
        expectationDescription: String = "Async operation",
        timeout: TimeInterval = 3,
        file: StaticString = #file,
        line: Int = #line,
        operation: @escaping () async throws -> Void
    ) {
        let expectation = self.expectation(description: expectationDescription)
        Task {
            do { try await operation() }
            catch {
                XCTFail("Error thrown while executing async function @ \(file):\(line): \(error)")
                Thread.callStackSymbols.forEach { print($0) }
            }
            expectation.fulfill()
        }
        self.wait(for: [expectation], timeout: timeout)
    }
}
#endif
