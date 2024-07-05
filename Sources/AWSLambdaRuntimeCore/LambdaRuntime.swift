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

import Logging
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix

/// `LambdaRuntime` manages the Lambda process lifecycle.
///
/// Use this API, if you build a higher level web framework which shall be able to run inside the Lambda environment.
public final class LambdaRuntime<Handler: LambdaHandler>: Sendable {
    private let eventLoop: EventLoop
    private let logger: Logger
    private let configuration: LambdaConfiguration

    private let handler: Handler

    /// Create a new `LambdaRuntime`.
    ///
    /// - parameters:
    ///     - handlerProvider: A provider of the ``Handler`` the `LambdaRuntime` will manage.
    ///     - eventLoop: An `EventLoop` to run the Lambda on.
    ///     - logger: A `Logger` to log the Lambda events.
    @inlinable
    public convenience init(
        handler: Handler
    ) {
        self.init(
            handler: handler,
            eventLoop: MultiThreadedEventLoopGroup.singleton.next(),
            logger: Logger(label: "Lambda"),
            configuration: .init()
        )
    }

    /// Create a new `LambdaRuntime`.
    ///
    /// - parameters:
    ///     - handlerProvider: A provider of the ``Handler`` the `LambdaRuntime` will manage.
    ///     - eventLoop: An `EventLoop` to run the Lambda on.
    ///     - logger: A `Logger` to log the Lambda events.
    @usableFromInline
    init(
        handler: Handler,
        eventLoop: EventLoop,
        logger: Logger,
        configuration: LambdaConfiguration
    ) {
        // TODO: Make public
        self.eventLoop = eventLoop
        self.logger = logger
        self.configuration = configuration

        self.handler = handler
    }

    public func run() async throws {
        let client = LambdaRuntimeClient(eventLoop: self.eventLoop, configuration: self.configuration.runtimeEngine)
        var logger = self.logger

        while !Task.isCancelled {
            let (invocation, request) = try await client.getNextInvocation(logger: self.logger)

            await withTaskGroup(of: Void.self) { taskGroup in

                let context = LambdaContext(
                    logger: logger,
                    eventLoop: self.eventLoop,
                    invocation: invocation,
                    taskGroup: taskGroup
                )

                let result: Result<LambdaResponse, any Error>
                do {
                    let response = try await self.handler.handle(request, context: context)
                    result = .success(response)

                } catch {
                    result = .failure(error)
                }

                do {
                    switch result {
                    case .success(let response):
                        switch response.backing {
                        case .none:
                            try await client.reportResults(logger: self.logger, invocation: invocation, result: .success(nil))

                        case .singleShot(let byteBuffer):
                            try await client.reportResults(logger: self.logger, invocation: invocation, result: .success(byteBuffer))

                        case .stream(let stream):
                            do {
                                let writer = Writable()
                                try await stream(LambdaResponse.Writer(backing: writer))
                            } catch {

                            }

                        }

                    case .failure(let failure):
                        try await client.reportResults(logger: self.logger, invocation: invocation, result: .failure(failure))
                    }
                } catch {

                }

                // drain our taskgroup before calling next
                while !taskGroup.isEmpty {
                    await taskGroup.next()
                }
            }

        }
    }
}
