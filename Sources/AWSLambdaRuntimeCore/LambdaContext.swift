//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2020 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Logging
import NIOCore

// MARK: - InitializationContext

extension Lambda {
    /// Lambda runtime initialization context.
    /// The Lambda runtime generates and passes the `InitializationContext` to the Lambda factory as an argument.
    public struct InitializationContext {
        /// `Logger` to log with
        ///
        /// - note: The `LogLevel` can be configured using the `LOG_LEVEL` environment variable.
        public let logger: Logger

        /// The `EventLoop` the Lambda is executed on. Use this to schedule work with.
        ///
        /// - note: The `EventLoop` is shared with the Lambda runtime engine and should be handled with extra care.
        ///         Most importantly the `EventLoop` must never be blocked.
        public let eventLoop: EventLoop

        /// `ByteBufferAllocator` to allocate `ByteBuffer`
        public let allocator: ByteBufferAllocator

        init(logger: Logger, eventLoop: EventLoop, allocator: ByteBufferAllocator) {
            self.eventLoop = eventLoop
            self.logger = logger
            self.allocator = allocator
        }

        /// This interface is not part of the public API and must not be used by adopters. This API is not part of semver versioning.
        public static func __forTestsOnly(
            logger: Logger,
            eventLoop: EventLoop
        ) -> InitializationContext {
            InitializationContext(
                logger: logger,
                eventLoop: eventLoop,
                allocator: ByteBufferAllocator()
            )
        }
    }
}

// MARK: - Context

/// Lambda runtime context.
/// The Lambda runtime generates and passes the `Context` to the Lambda handler as an argument.
public struct LambdaContext: CustomDebugStringConvertible {
    final class _Storage {
        var requestID: String
        var traceID: String
        var invokedFunctionARN: String
        var deadline: DispatchWallTime
        var cognitoIdentity: String?
        var clientContext: String?
        var logger: Logger
        var eventLoop: EventLoop
        var allocator: ByteBufferAllocator

        init(
            requestID: String,
            traceID: String,
            invokedFunctionARN: String,
            deadline: DispatchWallTime,
            cognitoIdentity: String?,
            clientContext: String?,
            logger: Logger,
            eventLoop: EventLoop,
            allocator: ByteBufferAllocator
        ) {
            self.requestID = requestID
            self.traceID = traceID
            self.invokedFunctionARN = invokedFunctionARN
            self.deadline = deadline
            self.cognitoIdentity = cognitoIdentity
            self.clientContext = clientContext
            self.logger = logger
            self.eventLoop = eventLoop
            self.allocator = allocator
        }
    }

    private var storage: _Storage

    /// The request ID, which identifies the request that triggered the function invocation.
    public var requestID: String {
        self.storage.requestID
    }

    /// The AWS X-Ray tracing header.
    public var traceID: String {
        self.storage.traceID
    }

    /// The ARN of the Lambda function, version, or alias that's specified in the invocation.
    public var invokedFunctionARN: String {
        self.storage.invokedFunctionARN
    }

    /// The timestamp that the function times out
    public var deadline: DispatchWallTime {
        self.storage.deadline
    }

    /// For invocations from the AWS Mobile SDK, data about the Amazon Cognito identity provider.
    public var cognitoIdentity: String? {
        self.storage.cognitoIdentity
    }

    /// For invocations from the AWS Mobile SDK, data about the client application and device.
    public var clientContext: String? {
        self.storage.clientContext
    }

    /// `Logger` to log with
    ///
    /// - note: The `LogLevel` can be configured using the `LOG_LEVEL` environment variable.
    public var logger: Logger {
        self.storage.logger
    }

    /// The `EventLoop` the Lambda is executed on. Use this to schedule work with.
    /// This is useful when implementing the `EventLoopLambdaHandler` protocol.
    ///
    /// - note: The `EventLoop` is shared with the Lambda runtime engine and should be handled with extra care.
    ///         Most importantly the `EventLoop` must never be blocked.
    public var eventLoop: EventLoop {
        self.storage.eventLoop
    }

    /// `ByteBufferAllocator` to allocate `ByteBuffer`
    /// This is useful when implementing `EventLoopLambdaHandler`
    public var allocator: ByteBufferAllocator {
        self.storage.allocator
    }

    init(requestID: String,
         traceID: String,
         invokedFunctionARN: String,
         deadline: DispatchWallTime,
         cognitoIdentity: String? = nil,
         clientContext: String? = nil,
         logger: Logger,
         eventLoop: EventLoop,
         allocator: ByteBufferAllocator) {
        self.storage = _Storage(
            requestID: requestID,
            traceID: traceID,
            invokedFunctionARN: invokedFunctionARN,
            deadline: deadline,
            cognitoIdentity: cognitoIdentity,
            clientContext: clientContext,
            logger: logger,
            eventLoop: eventLoop,
            allocator: allocator
        )
    }

    public func getRemainingTime() -> TimeAmount {
        let deadline = self.deadline.millisSinceEpoch
        let now = DispatchWallTime.now().millisSinceEpoch

        let remaining = deadline - now
        return .milliseconds(remaining)
    }

    public var debugDescription: String {
        "\(Self.self)(requestID: \(self.requestID), traceID: \(self.traceID), invokedFunctionARN: \(self.invokedFunctionARN), cognitoIdentity: \(self.cognitoIdentity ?? "nil"), clientContext: \(self.clientContext ?? "nil"), deadline: \(self.deadline))"
    }

    /// This interface is not part of the public API and must not be used by adopters. This API is not part of semver versioning.
    public static func __forTestsOnly(
        requestID: String,
        traceID: String,
        invokedFunctionARN: String,
        timeout: DispatchTimeInterval,
        logger: Logger,
        eventLoop: EventLoop
    ) -> LambdaContext {
        LambdaContext(
            requestID: requestID,
            traceID: traceID,
            invokedFunctionARN: invokedFunctionARN,
            deadline: .now() + timeout,
            logger: logger,
            eventLoop: eventLoop,
            allocator: ByteBufferAllocator()
        )
    }
}

extension LambdaContext {
    
    init(logger: Logger,
         eventLoop: EventLoop,
         allocator: ByteBufferAllocator,
         invocation: Invocation,
         invocationCount: Int) {
        
        self.init(
            requestID: invocation.requestID,
            traceID: invocation.traceID,
            invokedFunctionARN: invocation.invokedFunctionARN,
            deadline: .init(millisSinceEpoch: invocation.deadlineInMillisSinceEpoch),
            cognitoIdentity: invocation.cognitoIdentity,
            clientContext: invocation.clientContext,
            logger: logger,
            eventLoop: eventLoop,
            allocator: allocator
        )
    }
}

// MARK: - ShutdownContext

extension Lambda {
    /// Lambda runtime shutdown context.
    /// The Lambda runtime generates and passes the `ShutdownContext` to the Lambda handler as an argument.
    public final class ShutdownContext {
        /// `Logger` to log with
        ///
        /// - note: The `LogLevel` can be configured using the `LOG_LEVEL` environment variable.
        public let logger: Logger

        /// The `EventLoop` the Lambda is executed on. Use this to schedule work with.
        ///
        /// - note: The `EventLoop` is shared with the Lambda runtime engine and should be handled with extra care.
        ///         Most importantly the `EventLoop` must never be blocked.
        public let eventLoop: EventLoop

        internal init(logger: Logger, eventLoop: EventLoop) {
            self.eventLoop = eventLoop
            self.logger = logger
        }
    }
}
