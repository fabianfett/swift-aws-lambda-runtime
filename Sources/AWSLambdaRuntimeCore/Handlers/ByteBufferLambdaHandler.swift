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

// MARK: - ByteBufferLambdaHandler

/// An `EventLoopFuture` based processing protocol for a Lambda that takes a `ByteBuffer` and returns
/// an optional `ByteBuffer` asynchronously.
///
/// - note: This is a low level protocol designed to power the higher level ``EventLoopLambdaHandler`` and
///         ``LambdaHandler`` based APIs.
///         Most users are not expected to use this protocol.
public protocol ByteBufferLambdaHandler {
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
    ///     - event: The event or input payload encoded as `ByteBuffer`.
    ///
    /// - Returns: An `EventLoopFuture` to report the result of the Lambda back to the runtime engine.
    ///            The `EventLoopFuture` should be completed with either a response encoded as `ByteBuffer` or an `Error`.
    func handle(_ event: ByteBuffer, context: LambdaContext) -> EventLoopFuture<ByteBuffer?>
}

extension ByteBufferLambdaHandler {
    /// Initializes and runs the Lambda function.
    ///
    /// If you precede your ``ByteBufferLambdaHandler`` conformer's declaration with the
    /// [@main](https://docs.swift.org/swift-book/ReferenceManual/Attributes.html#ID626)
    /// attribute, the system calls the conformer's `main()` method to launch the lambda function.
    ///
    /// The lambda runtime provides a default implementation of the method that manages the launch
    /// process.
    public static func main() {
        _ = Lambda.run(configuration: .init(), handlerType: Self.self)
    }
}
