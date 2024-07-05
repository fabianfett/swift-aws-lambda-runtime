//
//  LambdaWriter.swift
//  swift-aws-lambda-runtime
//
//  Created by Fabian Fett on 26.06.24.
//

import NIOCore

final class Writable: Sendable {

    init() {

    }

    func write(_ byteBuffer: ByteBuffer) async throws {

    }

    enum GetBytesResult {
        case future(EventLoopFuture<ByteBuffer>)
        case bytes(ByteBuffer)
        case finished
    }

    func getBytes() -> GetBytesResult {
        fatalError("TODO: Unimplemented")
    }
}
