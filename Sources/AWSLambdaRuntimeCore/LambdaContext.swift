//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2017-2024 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

#if swift(<5.9)
@preconcurrency import Dispatch
#else
import Dispatch
#endif

import Logging
import NIOCore

/// Lambda runtime context.
/// The Lambda runtime generates and passes the `LambdaContext` to the Lambda handler as an argument.
public struct LambdaContext: CustomDebugStringConvertible {
    final class _Storage: Sendable {
        let requestID: String
        let traceID: String
        let invokedFunctionARN: String
        let deadline: DispatchWallTime
        let cognitoIdentity: String?
        let clientContext: String?
        let logger: Logger

        init(
            requestID: String,
            traceID: String,
            invokedFunctionARN: String,
            deadline: DispatchWallTime,
            cognitoIdentity: String?,
            clientContext: String?,
            logger: Logger
        ) {
            self.requestID = requestID
            self.traceID = traceID
            self.invokedFunctionARN = invokedFunctionARN
            self.deadline = deadline
            self.cognitoIdentity = cognitoIdentity
            self.clientContext = clientContext
            self.logger = logger
        }
    }
 
    private var storage: _Storage
    private var taskGroup: TaskGroup<Void>

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

    /// The timestamp that the function times out.
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

    /// `Logger` to log with.
    ///
    /// - note: The `LogLevel` can be configured using the `LOG_LEVEL` environment variable.
    public var logger: Logger {
        self.storage.logger
    }

    /// The `EventLoop` the Lambda is executed on. Use this to schedule work with.
    /// This is useful when implementing the ``EventLoopLambdaHandler`` protocol.
    ///
    /// - note: The `EventLoop` is shared with the Lambda runtime engine and should be handled with extra care.
    ///         Most importantly the `EventLoop` must never be blocked.
//    public var eventLoop: EventLoop {
//        self.storage.eventLoop
//    }

    public mutating func addBackgroundTask(_ closure: @escaping @Sendable () async -> ()) {
        self.taskGroup.addTask(operation: closure)
    }

    init(
        requestID: String,
        traceID: String,
        invokedFunctionARN: String,
        deadline: DispatchWallTime,
        cognitoIdentity: String? = nil,
        clientContext: String? = nil,
        logger: Logger,
        taskGroup: TaskGroup<Void>
    ) {
        self.storage = _Storage(
            requestID: requestID,
            traceID: traceID,
            invokedFunctionARN: invokedFunctionARN,
            deadline: deadline,
            cognitoIdentity: cognitoIdentity,
            clientContext: clientContext,
            logger: logger
        )
        self.taskGroup = taskGroup
    }

    public mutating func background(_ body: @escaping @Sendable () -> ()) {
        self.taskGroup.addTask(operation: body)
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
}

extension LambdaContext {
    @usableFromInline
    init(logger: Logger, invocation: Invocation, taskGroup: TaskGroup<Void>) {
        self.init(
            requestID: invocation.requestID,
            traceID: invocation.traceID,
            invokedFunctionARN: invocation.invokedFunctionARN,
            deadline: DispatchWallTime(millisSinceEpoch: invocation.deadlineInMillisSinceEpoch),
            cognitoIdentity: invocation.cognitoIdentity,
            clientContext: invocation.clientContext,
            logger: logger,
            taskGroup: taskGroup
        )
    }
}
