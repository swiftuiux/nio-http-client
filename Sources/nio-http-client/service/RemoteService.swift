//
//  RemoteService.swift
//
//
//  Created by Igor  on 28.06.24.
//

import Foundation
import NIO
import NIOHTTP1

public class RemoteService {
    private let eventLoopGroup: EventLoopGroup
    private let httpClient: HTTPClient

    public init(eventLoopGroup: EventLoopGroup, config: HTTPClientConfiguration) {
        self.eventLoopGroup = eventLoopGroup
        self.httpClient = HTTPClient(eventLoopGroup: eventLoopGroup, config: config)
    }

    func makeRequest(path: String, queryParams: String, method: HTTPMethod) async -> Result<Data, HTTPClientError> {
        return await httpClient.makeRequest(path: path, queryParams: queryParams, method: method)
    }
}
