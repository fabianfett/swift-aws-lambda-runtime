import NIOCore

struct HTTPResponseDecoder: NIOSingleStepByteToMessageDecoder {
    typealias InboundOut = APIResponse
    
    init() {
        
    }
    
    func decode(buffer: inout ByteBuffer) throws -> APIResponse? {
        return nil
    }
    
    func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> APIResponse? {
        return nil
    }
}
