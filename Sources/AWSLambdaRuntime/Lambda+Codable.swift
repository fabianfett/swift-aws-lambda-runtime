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

@_exported import AWSLambdaRuntimeCore
import struct Foundation.Data
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
import NIOCore
import NIOFoundationCompat

extension LambdaRuntime {
    public convenience init<
        Event: Decodable,
        Output: Encodable
    >(
        body: @escaping (Event, LambdaContext) async throws -> Output
    ) where Handler == CodableAdapter<CodableClosureHandler<Event, Output>, JSONDecoder, JSONEncoder> {
        self.init(
            decoder: JSONDecoder(),
            encoder: JSONEncoder(),
            body: body
        )
    }
}

extension JSONEncoder: AWSLambdaRuntimeCore.LambdaOutputEncoder {}

extension JSONDecoder: AWSLambdaRuntimeCore.LambdaEventDecoder {}
