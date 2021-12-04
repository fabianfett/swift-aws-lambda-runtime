//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2021 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

struct RuntimeStateMachine {
    private enum State {
        enum InvocationState {
            case waitingForNextInvocation
            case runningHandler(requestID: String)
            case reportingResult
        }
        
        case initialized(factory: (Lambda.InitializationContext) -> EventLoopFuture<ByteBufferLambdaHandler>)
        case starting(handler: Result<ByteBufferLambdaHandler, Error>?, connected: Bool)
        case started(handler: ByteBufferLambdaHandler)
        case running(ByteBufferLambdaHandler, state: InvocationState)
        case reportingInitializationError(Error)
        case shuttingDown
        case shutdown
    }

    enum Action {
        case connect(to: SocketAddress, promise: EventLoopPromise<Void>?, andInitializeHandler: (Lambda.InitializationContext) -> EventLoopFuture<ByteBufferLambdaHandler>)
        case reportStartupFailureToChannel(Error)
        
        case getNextInvocation(reportStartUpSuccess: Bool)
        case invokeHandler(ByteBufferLambdaHandler, Lambda.Invocation, ByteBuffer, Int)
        case reportInvocationResult(requestID: String, Result<ByteBuffer?, Error>)
        case reportInitializationError(Error)

        case closeConnection(Error?)
        case fireChannelInactive(Error?)
        case wait
    }

    private var state: State
    private var markShutdown: Bool = false
    private let maxTimes: Int
    private var invocationCount = 0

    init(maxTimes: Int, factory: @escaping (Lambda.InitializationContext) -> EventLoopFuture<ByteBufferLambdaHandler>) {
        self.maxTimes = maxTimes
        self.state = .initialized(factory: factory)
    }

    mutating func connect(to address: SocketAddress, promise: EventLoopPromise<Void>?) -> Action {
        switch self.state {
        case .initialized(let factory):
            self.state = .starting(handler: nil, connected: false)
            return .connect(to: address, promise: promise, andInitializeHandler: factory)
            
        case .starting,
             .started,
             .running,
             .shuttingDown,
             .reportingInitializationError,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func connected() -> Action {
        switch self.state {
        case .starting(.some(.success(let handler)), connected: false):
            self.state = .running(handler, state: .waitingForNextInvocation)
            return .getNextInvocation(reportStartUpSuccess: true)
            
        case .starting(.some(.failure(let error)), connected: false):
            self.state = .reportingInitializationError(error)
            return .reportInitializationError(error)
            
        case .starting(.none, connected: false):
            self.state = .starting(handler: .none, connected: true)
            return .wait
            
        case .initialized,
             .started,
             .starting(handler: _, connected: true),
             .running,
             .shuttingDown,
             .reportingInitializationError,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func handlerInitialized(_ handler: ByteBufferLambdaHandler) -> Action {
        switch self.state {
        case .starting(.none, connected: false):
            self.state = .starting(handler: .success(handler), connected: false)
            return .wait

        case .starting(.none, connected: true):
            self.state = .started(handler: handler)
            return .getNextInvocation(reportStartUpSuccess: true)

        case .initialized,
             .starting(handler: .some, connected: _),
             .started,
             .running,
             .shuttingDown,
             .reportingInitializationError,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func handlerFailedToInitialize(_ error: Error) -> Action {
        switch self.state {
        case .starting(.none, connected: false):
            self.state = .starting(handler: .failure(error), connected: false)
            return .wait

        case .starting(.none, connected: true):
            self.state = .reportingInitializationError(error)
            return .reportInitializationError(error)

        case .initialized,
             .starting(handler: .some, connected: _),
             .started,
             .running,
             .shuttingDown,
             .reportingInitializationError,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func nextInvocationReceived(_ invocation: Lambda.Invocation, _ bytes: ByteBuffer) -> Action {
        switch self.state {
        case .running(let handler, .waitingForNextInvocation):
            self.invocationCount += 1
            self.state = .running(handler, state: .runningHandler(requestID: invocation.requestID))
            return .invokeHandler(handler, invocation, bytes, self.invocationCount)
            
        case .initialized,
             .starting,
             .started,
             .running,
             .shuttingDown,
             .reportingInitializationError,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func invocationCompleted(_ result: Result<ByteBuffer?, Error>) -> Action {
        switch self.state {
        case .running(let handler, .runningHandler(let requestID)):
            self.state = .running(handler, state: .reportingResult)
            return .reportInvocationResult(requestID: requestID, result)
            
        case .initialized,
             .starting,
             .started,
             .running,
             .shuttingDown,
             .reportingInitializationError,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func acceptedReceived() -> Action {
        switch self.state {
        case .running(_, state: .reportingResult) where self.markShutdown == true || (self.maxTimes > 0 && self.invocationCount == self.maxTimes):
            self.state = .shuttingDown
            return .closeConnection(nil)
            
        case .running(let handler, state: .reportingResult):
            self.state = .running(handler, state: .waitingForNextInvocation)
            return .getNextInvocation(reportStartUpSuccess: false)
            
        case .reportingInitializationError(let error):
            self.state = .shuttingDown
            return .closeConnection(error)
        
        case .initialized,
             .starting,
             .started,
             .running(_, state: .waitingForNextInvocation),
             .running(_, state: .runningHandler),
             .shuttingDown,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func close() -> Action {
        switch self.state {
        case .running(_, state: .waitingForNextInvocation):
            self.state = .shuttingDown
            return .closeConnection(nil)

        case .running(_, state: _):
            self.markShutdown = true
            return .wait

        case .initialized,
             .starting,
             .started,
             .reportingInitializationError,
             .shuttingDown,
             .shutdown:
            preconditionFailure("Invalid state: \(self.state)")
        }
    }

    mutating func channelInactive() -> Action {
        switch self.state {
        case .shuttingDown:
            self.state = .shutdown
            return .fireChannelInactive(nil)

        case .initialized, .shutdown, .starting(_, connected: false):
            preconditionFailure("Invalid state: \(self.state)")

        case .starting(_, connected: true):
            preconditionFailure("Todo: Unexpected connection closure during startup")

        case .started:
            preconditionFailure("Todo: Unexpected connection closure during startup")

        case .running(_, state: .waitingForNextInvocation):
            self.state = .shutdown
            return .fireChannelInactive(nil)

        case .running(_, state: .runningHandler):
            preconditionFailure("Todo: Unexpected connection closure")

        case .running(_, state: .reportingResult):
            preconditionFailure("Todo: Unexpected connection closure")

        case .reportingInitializationError:
            preconditionFailure("Todo: Unexpected connection closure during startup")

        }
    }

    mutating func errorMessageReceived(_: ErrorResponse) -> Action {
        preconditionFailure()
    }

    mutating func errorHappened(_ error: Error) -> Action {
        self.state = .shuttingDown
        return .closeConnection(error)
    }
}
