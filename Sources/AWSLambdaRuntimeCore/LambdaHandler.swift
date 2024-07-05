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
import NIOCore

// MARK: - LambdaHandler

public struct LambdaResponse {
    public struct Writer {
        let backing: Writable

        func write(_ byteBuffer: ByteBuffer) async throws {
            try await self.backing.write(byteBuffer)
        }
    }

    enum Backing {
        case none
        case singleShot(ByteBuffer)
        case stream((Writer) async throws -> ())
    }

    let backing: Backing

    public init() {
        self.backing = .none
    }

    public init(_ byteBuffer: ByteBuffer) {
        self.backing = .singleShot(byteBuffer)
    }

    public init(_ stream: @escaping @Sendable (Writer) async throws -> ()) {
        self.backing = .stream(stream)
    }
}

@available(*, unavailable)
extension LambdaResponse: Sendable {}
@available(*, unavailable)
extension LambdaResponse.Writer: Sendable {}

public protocol LambdaHandler: Sendable {
    func handle(_ request: ByteBuffer, context: LambdaContext) async throws -> LambdaResponse
}
