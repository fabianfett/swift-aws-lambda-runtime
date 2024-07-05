//
//  LambdaWriter.swift
//  swift-aws-lambda-runtime
//
//  Created by Fabian Fett on 26.06.24.
//

import NIOCore

@usableFromInline
final actor Writable: Sendable {

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        self.eventLoop.executor.asUnownedSerialExecutor()
    }

    private let eventLoop: EventLoop

    @usableFromInline
    init(eventLoop: EventLoop) {
        self.eventLoop = eventLoop
    }

    func write(_ byteBuffer: ByteBuffer) async throws {

    }

    enum GetBytesResult {
        case future(EventLoopFuture<ByteBuffer>)
        case bytes(ByteBuffer)
        case finished
    }

    nonisolated func getBytes() -> GetBytesResult {

        self.assumeIsolated {
            
        }

        fatalError("TODO: Unimplemented")
    }
}
