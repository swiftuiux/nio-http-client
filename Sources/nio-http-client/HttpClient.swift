//
//  HttpClient.swift
//
//
//  Created by Igor  on 28.06.24.
//
import Foundation
import NIO
import NIOHTTP1

enum HTTPClientError: Error {
    case requestTimeout
    case networkError(Error)
    case serverError(Int)
    case invalidResponse
}

class HTTPClient {
    private let group: EventLoopGroup
    private let bootstrap: ClientBootstrap
    private var availableChannels: [Channel] = []
    private let config: HTTPClientConfiguration
    private let lock: DispatchQueue

    init(eventLoopGroup: EventLoopGroup, config: HTTPClientConfiguration) {
        self.group = eventLoopGroup
        self.config = config
        self.lock = DispatchQueue(label: "com.example.connectionPool.\(UUID().uuidString)")
        self.bootstrap = ClientBootstrap(group: group)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers().flatMap {
                    channel.pipeline.addHandler(HTTPClientHandler(config: self.config))
                }
            }
    }

    func getChannel() -> EventLoopFuture<Channel> {
        return lock.sync {
            if let channel = availableChannels.popLast() {
                return group.next().makeSucceededFuture(channel)
            } else {
                return bootstrap.connect(host: config.host, port: config.port).map { channel in
                    channel.closeFuture.whenComplete { _ in
                        self.releaseChannel(channel)
                    }
                    return channel
                }
            }
        }
    }

    private func releaseChannel(_ channel: Channel) {
        lock.async {
            if self.availableChannels.count < self.config.maxOpenChannels {
                self.availableChannels.append(channel)
            } else {
                try? channel.close().wait()
            }
        }
    }

    func makeRequest(path: String, queryParams: String, method: HTTPMethod, body: String? = nil) async -> Result<Data, HTTPClientError> {
        do {
            let channel = try await getChannel().get()
            var requestHead = self.config.createRequestHead(method: method, uri: "\(path)?\(queryParams)")
            let promise = self.group.next().makePromise(of: Void.self)
            
            if let body = body {
                let buffer = channel.allocator.buffer(string: body)
                requestHead.headers.add(name: "Content-Length", value: "\(buffer.readableBytes)")
                channel.write(NIOAny(HTTPClientRequestPart.head(requestHead))).flatMap {
                    channel.write(NIOAny(HTTPClientRequestPart.body(.byteBuffer(buffer))))
                }.flatMap {
                    channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)))
                }.whenComplete { result in
                    switch result {
                    case .success:
                        promise.succeed(())
                    case .failure(let error):
                        promise.fail(HTTPClientError.networkError(error))
                    }
                }
            } else {
                channel.write(NIOAny(HTTPClientRequestPart.head(requestHead))).flatMap {
                    channel.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)))
                }.whenComplete { result in
                    switch result {
                    case .success:
                        promise.succeed(())
                    case .failure(let error):
                        promise.fail(HTTPClientError.networkError(error))
                    }
                }
            }
            
            let timeoutFuture = self.group.next().scheduleTask(in: self.config.timeout) {
                promise.fail(HTTPClientError.requestTimeout)
            }
            
            try await promise.futureResult.get()
            timeoutFuture.cancel()
            
            var responseData = Data()
            channel.pipeline.addHandler(ByteToMessageHandler(HTTPResponseDecoder())).flatMap {
                channel.pipeline.addHandler(CollectHTTPResponseDataHandler { data in
                    responseData.append(contentsOf: data)
                })
            }.whenComplete { _ in
                // Response data collected
            }
            
            return .success(responseData)
        } catch let error as HTTPClientError {
            return .failure(error)
        } catch {
            return .failure(.networkError(error))
        }
    }

    deinit {
        // Close all available channels when HTTPClient is deinitialized
        for channel in availableChannels {
            try? channel.close().wait()
        }
    }
}

final class HTTPClientHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPClientResponsePart
    var responseData: Data = Data()
    let config: HTTPClientConfiguration

    init(config: HTTPClientConfiguration) {
        self.config = config
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let response = self.unwrapInboundIn(data)
        
        switch response {
        case .head(let header):
            if !(200..<300).contains(header.status.code) {
                context.fireErrorCaught(HTTPClientError.serverError(Int(header.status.code)))
            }
        case .body(let body):
            if let bytes = body.getBytes(at: body.readerIndex, length: body.readableBytes) {
                responseData.append(contentsOf: bytes)
            }
        case .end:
            context.fireChannelRead(NIOAny(responseData))
            context.close(promise: nil)
        }
    }
}
