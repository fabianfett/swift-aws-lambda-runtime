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

public protocol _TypedLambdaHandlerBase {
    /// The lambda functions input. In most cases this should be `Codable`. If your event originates from an
    /// AWS service, have a look at [AWSLambdaEvents](https://github.com/swift-server/swift-aws-lambda-events),
    /// which provides a number of commonly used AWS Event implementations.
    associatedtype Event
    /// The lambda functions output. Can be `Void`.
    associatedtype Output

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

#if compiler(>=5.5) && canImport(_Concurrency)
/// Strongly typed, processing protocol for a Lambda that takes a user defined
/// ``EventLoopLambdaHandler/Event`` and returns a user defined
/// ``EventLoopLambdaHandler/Output`` asynchronously.
///
/// - note: Most users should implement this protocol instead of the lower
///         level protocols ``EventLoopLambdaHandler`` and
///         ``ByteBufferLambdaHandler``.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
public protocol LifecycleLambdaHandler: _TypedLambdaHandlerBase {
    /// The lambda functions input. In most cases this should be `Codable`. If your event originates from an
    /// AWS service, have a look at [AWSLambdaEvents](https://github.com/swift-server/swift-aws-lambda-events),
    /// which provides a number of commonly used AWS Event implementations.
    associatedtype Event
    /// The lambda functions output. Can be `Void`.
    associatedtype Output

    /// The Lambda initialization method.
    /// Use this method to initialize resources that will be used in every request.
    ///
    /// Examples for this can be HTTP or database clients.
    /// - parameters:
    ///     - context: Runtime ``LambdaInitializationContext``.
    init(context: LambdaInitializationContext) async throws

    /// The Lambda handling method.
    /// Concrete Lambda handlers implement this method to provide the Lambda functionality.
    ///
    /// - parameters:
    ///     - event: Event of type `Event` representing the event or request.
    ///     - context: Runtime ``LambdaContext``.
    ///
    /// - Returns: A Lambda result ot type `Output`.
    func handle(_ event: Event, context: LambdaContext) async throws -> Output
}

/// Implementation of  `ByteBuffer` to `Void` decoding.
@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension LifecycleLambdaHandler where Output == Void {
    @inlinable
    public func encode(value: Void, into byteBuffer: inout ByteBuffer) throws {}
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
final class LifeycleLambdaHandlerAdapter<Underlying: LifecycleLambdaHandler, Event, Output>: ByteBufferLambdaHandler
    where Underlying.Event == Event, Underlying.Output == Output
{
    let handler: Underlying

    var outgoing: ByteBuffer

    @inlinable
    static func makeHandler(context: LambdaInitializationContext) -> EventLoopFuture<LifeycleLambdaHandlerAdapter<Underlying, Event, Output>> {
        let buffer = context.allocator.buffer(capacity: 1024 * 1024)
        let promise = context.eventLoop.makePromise(of: LifeycleLambdaHandlerAdapter<Underlying, Event, Output>.self)
        promise.completeWithTask {
            let handler = try await Underlying(context: context)
            return LifeycleLambdaHandlerAdapter(handler: handler, outgoing: buffer)
        }
        return promise.futureResult
    }

    @inlinable
    init(handler: Underlying, outgoing: ByteBuffer) {
        self.handler = handler
        self.outgoing = outgoing
    }

    @inlinable
    func handle(_ event: ByteBuffer, context: LambdaContext) -> EventLoopFuture<ByteBuffer?> {
        let promise = context.eventLoop.makePromise(of: ByteBuffer?.self)
        promise.completeWithTask {
            let input: Event
            do {
                input = try self.handler.decode(buffer: event)
            } catch {
                throw CodecError.requestDecoding(error)
            }

            let output = try await self.handler.handle(input, context: context)

            do {
                self.outgoing.clear()
                try self.handler.encode(value: output, into: &self.outgoing)
                return self.outgoing
            } catch {
                throw CodecError.responseEncoding(error)
            }
        }
        return promise.futureResult
    }
}

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension LifeycleLambdaHandlerAdapter where Output == Void {
    @inlinable
    static func makeHandler(context: LambdaInitializationContext) -> EventLoopFuture<LifeycleLambdaHandlerAdapter<Underlying, Event, Output>> {
        let buffer = context.allocator.buffer(capacity: 0)
        let promise = context.eventLoop.makePromise(of: LifeycleLambdaHandlerAdapter<Underlying, Event, Output>.self)
        promise.completeWithTask {
            let handler = try await Underlying(context: context)
            return LifeycleLambdaHandlerAdapter(handler: handler, outgoing: buffer)
        }
        return promise.futureResult
    }

    @inlinable
    func handle(_ event: ByteBuffer, context: LambdaContext) -> EventLoopFuture<ByteBuffer?> {
        let promise = context.eventLoop.makePromise(of: ByteBuffer?.self)
        promise.completeWithTask {
            let input: Event
            do {
                input = try self.handler.decode(buffer: event)
            } catch {
                throw CodecError.requestDecoding(error)
            }

            try await self.handler.handle(input, context: context)
            return nil
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
