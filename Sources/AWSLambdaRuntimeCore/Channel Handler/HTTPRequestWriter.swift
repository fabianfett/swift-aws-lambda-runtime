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
import NIOHTTP1

struct HTTPRequestWriter: APIRequestWriter {
    typealias OutboundOut = ByteBuffer
    
    private var host: String
    private var byteBuffer: ByteBuffer!
    
    init(host: String) {
        self.host = host
    }
    
    mutating func writeRequest(_ request: APIRequest, context: ChannelHandlerContext) {
        self.byteBuffer.clear(minimumCapacity: self.byteBuffer.storageCapacity)
        
        switch request {
        case .next:
            self.byteBuffer.writeStaticString(.nextInvocationRequestLine)
            self.byteBuffer.writeHostHeader(host: self.host)
            self.byteBuffer.writeStaticString(.userAgentHeader)
            self.byteBuffer.writeStaticString(.CRLF) // end of head
            context.write(self.wrapOutboundOut(self.byteBuffer), promise: nil)
            context.flush()

        case .invocationResponse(let requestID, let payload):
            let contentLength = payload?.readableBytes ?? 0
            self.byteBuffer.writeInvocationResultRequestLine(requestID)
            self.byteBuffer.writeContentLengthHeader(length: contentLength)
            self.byteBuffer.writeHostHeader(host: self.host)
            self.byteBuffer.writeStaticString(.userAgentHeader)
            self.byteBuffer.writeStaticString(.CRLF) // end of head
            context.write(self.wrapOutboundOut(self.byteBuffer), promise: nil)
            if contentLength > 0 {
                context.write(self.wrapOutboundOut(payload!), promise: nil)
            }
            context.flush()

        case .invocationError(let requestID, let errorMessage):
            let payload = errorMessage.toJSONBytes()
            self.byteBuffer.writeInvocationErrorRequestLine(requestID)
            self.byteBuffer.writeContentLengthHeader(length: payload.count)
            self.byteBuffer.writeHostHeader(host: self.host)
            self.byteBuffer.writeStaticString(.userAgentHeader)
            self.byteBuffer.writeStaticString(.unhandledErrorHeader)
            self.byteBuffer.writeStaticString(.CRLF) // end of head
            self.byteBuffer.writeBytes(payload)
            context.write(self.wrapOutboundOut(self.byteBuffer), promise: nil)
            context.flush()

        case .initializationError(let errorMessage):
            let payload = errorMessage.toJSONBytes()
            self.byteBuffer.writeStaticString(.runtimeInitErrorRequestLine)
            self.byteBuffer.writeContentLengthHeader(length: payload.count)
            self.byteBuffer.writeHostHeader(host: self.host)
            self.byteBuffer.writeStaticString(.userAgentHeader)
            self.byteBuffer.writeStaticString(.unhandledErrorHeader)
            self.byteBuffer.writeStaticString(.CRLF) // end of head
            self.byteBuffer.writeBytes(payload)
            context.write(self.wrapOutboundOut(self.byteBuffer), promise: nil)
            context.flush()
        }
    }
    
    mutating func writerAdded(context: ChannelHandlerContext) {
        self.byteBuffer = context.channel.allocator.buffer(capacity: 256)
    }
    
    mutating func writerRemoved(context: ChannelHandlerContext) {
        self.byteBuffer = nil
    }
}

extension ByteBuffer {
    
    fileprivate mutating func writeInvocationResultRequestLine(_ requestID: String) {
        self.writeStaticString("POST /2018-06-01/runtime/invocation/")
        self.writeString(requestID)
        self.writeStaticString("/response HTTP/1.1\r\n")
    }
    
    fileprivate mutating func writeInvocationErrorRequestLine(_ requestID: String) {
        self.writeStaticString("POST /2018-06-01/runtime/invocation/")
        self.writeString(requestID)
        self.writeStaticString("/error HTTP/1.1\r\n")
    }
    
    fileprivate mutating func writeHostHeader(host: String) {
        self.writeStaticString("host: ")
        self.writeString(host)
        self.writeStaticString(.CRLF)
    }
    
    fileprivate mutating func writeContentLengthHeader(length: Int) {
        self.writeStaticString("content-length: ")
        self.writeString("\(length)")
        self.writeStaticString(.CRLF)
    }
    
}

extension StaticString {
    static let CRLF: StaticString = "\r\n"
    
    static let userAgentHeader: StaticString = "user-agent: Swift-Lambda/Unknown\r\n"
    static let unhandledErrorHeader: StaticString = "lambda-runtime-function-error-type: Unhandled\r\n"
    
    static let nextInvocationRequestLine: StaticString =
        "GET /2018-06-01/runtime/invocation/next HTTP/1.1\r\n"
    
    static let runtimeInitErrorRequestLine: StaticString =
        "POST /2018-06-01/runtime/init/error HTTP/1.1\r\n"
}

struct HTTPRequestPartWriter: APIRequestWriter {
    typealias OutboundOut = HTTPClientRequestPart
    
    private var host: String
    
    init(host: String) {
        self.host = host
    }
    
    mutating func writeRequest(_ request: APIRequest, context: ChannelHandlerContext) {
        switch request {
        case .next:
            let head = HTTPRequestHead(
                version: .http1_1,
                method: .GET,
                uri: "/2018-06-01/runtime/invocation/next",
                headers: [
                    "host": self.host,
                    "user-agent": "Swift-Lambda/Unknown"
                ]
            )
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()

        case .invocationResponse(let requestID, let payload):
            let head = HTTPRequestHead(
                version: .http1_1,
                method: .POST,
                uri: "/2018-06-01/runtime/invocation/\(requestID)/response",
                headers: [
                    "content-length": "\(payload?.readableBytes ?? 0)",
                    "host": self.host,
                    "user-agent": "Swift-Lambda/Unknown"
                ]
            )
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            if let payload = payload {
                context.write(self.wrapOutboundOut(.body(.byteBuffer(payload))), promise: nil)
            }
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()

        case .invocationError(let requestID, let errorMessage):
            let payload = errorMessage.toJSONBytes()
            let head = HTTPRequestHead(
                version: .http1_1,
                method: .POST,
                uri: "/2018-06-01/runtime/invocation/\(requestID)/error",
                headers: [
                    "content-length": "\(payload.count)",
                    "host": self.host,
                    "user-agent": "Swift-Lambda/Unknown",
                    "lambda-runtime-function-error-type": "Unhandled",
                ]
            )
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            let bodyBuffer = context.channel.allocator.buffer(bytes: payload)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(bodyBuffer))), promise: nil)
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()

        case .initializationError(let errorMessage):
            let payload = errorMessage.toJSONBytes()
            let head = HTTPRequestHead(
                version: .http1_1,
                method: .POST,
                uri: "/2018-06-01/runtime/init/error",
                headers: [
                    "content-length": "\(payload.count)",
                    "host": self.host,
                    "user-agent": "Swift-Lambda/Unknown",
                    "lambda-runtime-function-error-type": "Unhandled",
                ]
            )
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            let bodyBuffer = context.channel.allocator.buffer(bytes: payload)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(bodyBuffer))), promise: nil)
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()
        }
    }
    
    mutating func writerAdded(context: ChannelHandlerContext) {}
    
    mutating func writerRemoved(context: ChannelHandlerContext) {}

}
