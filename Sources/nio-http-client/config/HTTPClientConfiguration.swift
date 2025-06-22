//
//  HTTPClientConfiguration.swift
//
//
//  Created by Igor  on 28.06.24.
//

import NIO
import NIOHTTP1

public class HTTPClientConfiguration {
    let host: String
    let port: Int
    let userAgent: String
    let accept: String
    let maxOpenChannels: Int
    let timeout: TimeAmount

    public init(host: String, port: Int, userAgent: String, accept: String, maxOpenChannels: Int = 10, timeout: TimeAmount) {
        self.host = host
        self.port = port
        self.userAgent = userAgent
        self.accept = accept
        self.maxOpenChannels = maxOpenChannels
        self.timeout = timeout
    }

    func createRequestHead(method: HTTPMethod, uri: String) -> HTTPRequestHead {
        var requestHead = HTTPRequestHead(version: .http1_1, method: method, uri: uri)
        requestHead.headers.add(name: "Host", value: host)
        requestHead.headers.add(name: "User-Agent", value: userAgent)
        requestHead.headers.add(name: "Accept", value: accept)
        return requestHead
    }
}

