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

import Dispatch
import Logging
import NIOCore

@usableFromInline
internal struct LambdaConfiguration: Sendable, CustomStringConvertible {
    let runtimeEngine: RuntimeEngine

    @usableFromInline
    init() {
        self.init(runtimeEngine: .init())
    }

    init(runtimeEngine: RuntimeEngine? = nil) {
        self.runtimeEngine = runtimeEngine ?? RuntimeEngine()
    }

    struct RuntimeEngine: Sendable, CustomStringConvertible {
        let ip: String
        let port: Int
        let requestTimeout: TimeAmount?

        init(address: String? = nil, keepAlive: Bool? = nil, requestTimeout: TimeAmount? = nil) {
            let ipPort = (address ?? Lambda.env("AWS_LAMBDA_RUNTIME_API"))?.split(separator: ":") ?? ["127.0.0.1", "7000"]
            guard ipPort.count == 2, let port = Int(ipPort[1]) else {
                preconditionFailure("invalid ip+port configuration \(ipPort)")
            }
            self.ip = String(ipPort[0])
            self.port = port
            self.requestTimeout = requestTimeout ?? Lambda.env("REQUEST_TIMEOUT").flatMap(Int64.init).flatMap { .milliseconds($0) }
        }

        var description: String {
            "\(RuntimeEngine.self)(ip: \(self.ip), port: \(self.port), requestTimeout: \(String(describing: self.requestTimeout))"
        }
    }

    @usableFromInline
    var description: String {
        "\(Self.self)\n  \(self.runtimeEngine)"
    }
}
