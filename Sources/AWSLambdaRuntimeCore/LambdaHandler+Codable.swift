//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftAWSLambdaRuntime open source project
//
// Copyright (c) 2024 Apple Inc. and the SwiftAWSLambdaRuntime project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftAWSLambdaRuntime project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

public protocol LambdaEventDecoder {
    func decode<T: Decodable>(_ type: T.Type, from buffer: ByteBuffer) throws -> T
}

public protocol LambdaOutputEncoder {
    func encode<T: Encodable>(_ value: T, into buffer: inout ByteBuffer) throws
}

public protocol CodableLambdaHandler {
    associatedtype Event: Decodable
    associatedtype Output: Encodable

    func handle(_ event: Event, context: LambdaContext) async throws -> Output
}

public struct CodableAdapter<
    Handler: CodableLambdaHandler,
    Decoder: LambdaEventDecoder,
    Encoder: LambdaOutputEncoder
>: LambdaHandler {
    let handler: Handler
    let encoder: Encoder
    let decoder: Decoder

    init(handler: Handler, encoder: Encoder, decoder: Decoder) {
        self.handler = handler
        self.encoder = encoder
        self.decoder = decoder
    }

    public func handle(_ request: ByteBuffer, context: LambdaContext) async throws -> LambdaResponse {
        fatalError()
    }
}

public struct CodableClosureHandler<Event: Decodable, Output: Encodable>: CodableLambdaHandler {
    let body: (Event, LambdaContext) async throws -> Output

    public init(body: @escaping (Event, LambdaContext) async throws -> Output) {
        self.body = body
    }

    public func handle(_ event: Event, context: LambdaContext) async throws -> Output {
        try await self.body(event, context)
    }
}

extension LambdaRuntime {
    public convenience init<
        Event: Decodable,
        Output: Encodable,
        EventDecoder: LambdaEventDecoder,
        OutputEncoder: LambdaOutputEncoder
    >(
        decoder: EventDecoder,
        encoder: OutputEncoder,
        body: @escaping (Event, LambdaContext) async throws -> Output
    ) where Handler == CodableAdapter<CodableClosureHandler<Event, Output>, EventDecoder, OutputEncoder> {
        let handler = CodableAdapter(
            handler: CodableClosureHandler<Event, Output>(body: body),
            encoder: encoder,
            decoder: decoder
        )
        self.init(handler: handler)
    }
}
