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

// MARK: - EventLoopLambdaHandler

/// Strongly typed, `EventLoopFuture` based processing protocol for a Lambda that takes a user
/// defined ``Event`` and returns a user defined ``Output`` asynchronously.
///
/// ``EventLoopLambdaHandler`` extends ``ByteBufferLambdaHandler``, performing
/// `ByteBuffer` -> ``Event`` decoding and ``Output`` -> `ByteBuffer` encoding.
///
/// - note: To implement a Lambda, implement either ``LambdaHandler`` or the
///         ``EventLoopLambdaHandler`` protocol. The ``LambdaHandler`` will offload
///         the Lambda execution to an async Task making processing safer but slower (due to
///         fewer thread hops).
///         The ``EventLoopLambdaHandler`` will execute the Lambda on the same `EventLoop`
///         as the core runtime engine, making the processing faster but requires more care from the
///         implementation to never block the `EventLoop`. Implement this protocol only in performance
///         critical situations and implement ``LambdaHandler`` in all other circumstances.
public protocol EventLoopLambdaHandler {
    /// The lambda functions input. In most cases this should be `Codable`. If your event originates from an
    /// AWS service, have a look at [AWSLambdaEvents](https://github.com/swift-server/swift-aws-lambda-events),
    /// which provides a number of commonly used AWS Event implementations.
    associatedtype Event
    /// The lambda functions output. Can be `Void`.
    associatedtype Output

    /// Create your Lambda handler for the runtime.
    ///
    /// Use this to initialize all your resources that you want to cache between invocations. This could be database
    /// connections and HTTP clients for example. It is encouraged to use the given `EventLoop`'s conformance
    /// to `EventLoopGroup` when initializing NIO dependencies. This will improve overall performance, as it
    /// minimizes thread hopping.
    static func makeHandler(context: LambdaInitializationContext) -> EventLoopFuture<Self>

    /// The Lambda handling method.
    /// Concrete Lambda handlers implement this method to provide the Lambda functionality.
    ///
    /// - parameters:
    ///     - context: Runtime ``LambdaContext``.
    ///     - event: Event of type `Event` representing the event or request.
    ///
    /// - Returns: An `EventLoopFuture` to report the result of the Lambda back to the runtime engine.
    ///            The `EventLoopFuture` should be completed with either a response of type ``Output`` or an `Error`.
    func handle(_ event: Event, context: LambdaContext) -> EventLoopFuture<Output>

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

final class CodableLambdaHandler<Underlying: EventLoopLambdaHandler, Event, Output>: ByteBufferLambdaHandler
    where Underlying.Event == Event, Underlying.Output == Output
{
    let handler: Underlying

    var outgoing: ByteBuffer

    @inlinable
    static func makeHandler(context: LambdaInitializationContext) -> EventLoopFuture<CodableLambdaHandler<Underlying, Event, Output>> {
        Underlying.makeHandler(context: context).map { handler -> CodableLambdaHandler<Underlying, Event, Output> in
            let buffer = context.allocator.buffer(capacity: 1024 * 1024)
            return CodableLambdaHandler(handler: handler, outgoing: buffer)
        }
    }

    @inlinable
    init(handler: Underlying, outgoing: ByteBuffer) {
        self.handler = handler
        self.outgoing = outgoing
    }

    @inlinable
    func handle(_ event: ByteBuffer, context: LambdaContext) -> EventLoopFuture<ByteBuffer?> {
        let input: Event
        do {
            input = try self.handler.decode(buffer: event)
        } catch {
            return context.eventLoop.makeFailedFuture(CodecError.requestDecoding(error))
        }

        return self.handler.handle(input, context: context).flatMapThrowing { output in
            do {
                self.outgoing.clear()
                try self.handler.encode(value: output, into: &self.outgoing)
                return self.outgoing
            } catch {
                throw CodecError.responseEncoding(error)
            }
        }
    }
}

extension CodableLambdaHandler where Output == Void {
    @inlinable
    static func makeHandler(context: LambdaInitializationContext) -> EventLoopFuture<CodableLambdaHandler<Underlying, Event, Output>> {
        Underlying.makeHandler(context: context).map { handler -> CodableLambdaHandler<Underlying, Event, Output> in
            let buffer = context.allocator.buffer(capacity: 0)
            return CodableLambdaHandler(handler: handler, outgoing: buffer)
        }
    }

    @inlinable
    func handle(_ event: ByteBuffer, context: LambdaContext) -> EventLoopFuture<ByteBuffer?> {
        let input: Event
        do {
            input = try self.handler.decode(buffer: event)
        } catch {
            return context.eventLoop.makeFailedFuture(CodecError.requestDecoding(error))
        }
        return self.handler.handle(input, context: context).map { _ in nil }
    }
}

/// Implementation of  `ByteBuffer` to `Void` decoding.
extension EventLoopLambdaHandler where Output == Void {
    @inlinable
    public func encode(value: Void, into byteBuffer: inout ByteBuffer) throws {}
}

@usableFromInline
enum CodecError: Error {
    case requestDecoding(Error)
    case responseEncoding(Error)
}
