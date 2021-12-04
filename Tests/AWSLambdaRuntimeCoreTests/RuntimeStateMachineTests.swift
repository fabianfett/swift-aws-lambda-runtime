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

@testable import AWSLambdaRuntimeCore
import NIOCore
import XCTest

final class RuntimeStateMachineTests: XCTestCase {
    
    struct HelloWorldLambdaHandler: EventLoopLambdaHandler {
        typealias Event = String
        typealias Output = String
        
        func handle(_ event: String, context: LambdaContext) -> EventLoopFuture<String> {
            context.eventLoop.makeSucceededFuture("Hello world!")
        }
    }
    
    let factoryPlaceHolder: (Lambda.InitializationContext) -> EventLoopFuture<ByteBufferLambdaHandler> = {
        $0.eventLoop.makeSucceededFuture(HelloWorldLambdaHandler())
    }
    
    func testRunHappyPath() {
//        var state = RuntimeStateMachine(maxTimes: 0, factory: self.factoryPlaceHolder)
        
    }
    
    
}

extension RuntimeStateMachine.Action {
    
    
    
    
}
