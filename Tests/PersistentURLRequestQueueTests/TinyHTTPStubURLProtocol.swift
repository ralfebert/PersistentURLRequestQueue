// MIT License
//
// Copyright (c) 2023 Ralf Ebert
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation

struct StubbedResponse {
    let response: HTTPURLResponse
    let data: Data
}

typealias RequestHandler = (_ request: URLRequest) -> StubbedResponse

class TinyHTTPStubURLProtocol: URLProtocol {
    static var urls = [URL: RequestHandler]()

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return self.urls.keys.contains(url)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override class func requestIsCacheEquivalent(_: URLRequest, to _: URLRequest) -> Bool {
        false
    }

    override func startLoading() {
        guard let client = client, let url = request.url, let handler = TinyHTTPStubURLProtocol.urls[url] else {
            fatalError()
        }

        let response = handler(request)
        client.urlProtocol(self, didReceive: response.response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: response.data)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
