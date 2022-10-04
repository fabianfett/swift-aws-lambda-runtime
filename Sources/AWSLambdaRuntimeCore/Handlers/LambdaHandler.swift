//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2022 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

// MARK: - LambdaHandler

#if compiler(>=5.5) && canImport(_Concurrency)
/// Strongly typed, processing protocol for a Lambda that takes a user defined
/// ``EventLoopLambdaHandler/Event`` and returns a user defined
/// ``EventLoopLambdaHandler/Output`` asynchronously.
///
/// - note: Most users should implement this protocol instead of the lower
///         level protocols ``EventLoopLambdaHandler`` and
///         ``ByteBufferLambdaHandler``.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol LambdaHandler {
    /// The lambda functions input. In most cases this should be `Codable`. If your event originates from an
    /// AWS service, have a look at [AWSLambdaEvents](https://github.com/swift-server/swift-aws-lambda-events),
    /// which provides a number of commonly used AWS Event implementations.
    associatedtype Event
    /// The lambda functions output. Can be `Void`.
    associatedtype Output

    /// The Lambda initialization method.
    /// Use this method to initialize resources that will be used in every request.
    init()

    /// The Lambda handling method.
    /// Concrete Lambda handlers implement this method to provide the Lambda functionality.
    ///
    /// - parameters:
    ///     - event: Event of type `Event` representing the event or request.
    ///     - context: Runtime ``LambdaContext``.
    ///
    /// - Returns: A Lambda result ot type `Output`.
    func handle(_ event: Event, context: LambdaContext) async throws -> Output

    /// Encode a response of type ``Output`` to `ByteBuffer`.
    /// Concrete Lambda handlers implement this method to provide coding functionality.
    /// - parameters:
    ///     - allocator: A `ByteBufferAllocator` to help allocate the `ByteBuffer`.
    ///     - value: Response of type ``Output``.
    ///
    /// - Returns: A `ByteBuffer` with the encoded version of the `value`.
    func encode(value: Output, into byteBuffer: inout ByteBuffer) throws

    /// Decode a `ByteBuffer` to a request or event of type ``Event``.
    /// Concrete Lambda handlers implement this method to provide coding functionality.
    ///
    /// - parameters:
    ///     - buffer: The `ByteBuffer` to decode.
    ///
    /// - Returns: A request or event of type ``Event``.
    func decode(buffer: ByteBuffer) throws -> Event
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension LambdaHandler {
    public static func makeHandler(context: LambdaInitializationContext) -> EventLoopFuture<Self> {
        let promise = context.eventLoop.makePromise(of: Self.self)
        promise.completeWithTask {
            Self()
        }
        return promise.futureResult
    }

    public func handle(_ event: Event, context: LambdaContext) -> EventLoopFuture<Output> {
        let promise = context.eventLoop.makePromise(of: Output.self)
        // using an unchecked sendable wrapper for the handler
        // this is safe since lambda runtime is designed to calls the handler serially
        let handler = UncheckedSendableHandler(underlying: self)
        promise.completeWithTask {
            try await handler.handle(event, context: context)
        }
        return promise.futureResult
    }
}

/// unchecked sendable wrapper for the handler
/// this is safe since lambda runtime is designed to calls the handler serially
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
fileprivate struct UncheckedSendableHandler<Underlying: LambdaHandler, Event, Output>: @unchecked Sendable where Event == Underlying.Event, Output == Underlying.Output {
    let underlying: Underlying

    init(underlying: Underlying) {
        self.underlying = underlying
    }

    func handle(_ event: Event, context: LambdaContext) async throws -> Output {
        try await self.underlying.handle(event, context: context)
    }
}
#endif
