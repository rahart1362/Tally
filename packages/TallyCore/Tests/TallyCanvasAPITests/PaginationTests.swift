import Foundation
import Testing
@testable import TallyCanvasAPI

@Suite("Link-header pagination and page URL policy")
struct PaginationTests {
    private func response(link: String?, headerName: String = "Link") -> HTTPResponse {
        var headers = HTTPHeaders()
        headers[headerName] = link
        return HTTPResponse(status: 200, headers: headers)
    }

    @Test(arguments: ["Link", "link", "LINK"])
    func headerNameIsCaseInsensitive(_ name: String) {
        let r = response(link: #"<https://c.example/api/v1/courses?page=2>; rel="next""#, headerName: name)
        #expect(LinkHeader.nextURL(in: r)?.absoluteString == "https://c.example/api/v1/courses?page=2")
    }

    @Test func findsNextAmongOtherRelsAndKeepsURLOpaque() {
        let next = "https://c.example/api/v1/courses?page=bookmark:WzEyM10&per_page=100&include%5B%5D=a,b"
        let header = #"<https://c.example/x?page=1>; rel="current", <\#(next)>; rel="next", <https://c.example/x?page=1>; rel="first""#
        #expect(LinkHeader.nextURL(in: response(link: header))?.absoluteString == next)
    }

    @Test(arguments: [#"<https://c.example/p2>; rel=next"#, #"<https://c.example/p2>; REL="NEXT""#, #"<https://c.example/p2>; rel="next last""#])
    func relVariants(_ header: String) {
        #expect(LinkHeader.nextURL(in: response(link: header))?.absoluteString == "https://c.example/p2")
    }

    @Test(arguments: [nil, "", #"<https://c.example/p1>; rel="current""#, "garbage", #"https://c.example/p2; rel="next""#])
    func noNextPage(_ header: String?) {
        #expect(LinkHeader.nextURL(in: response(link: header)) == nil)
    }

    @Test func acceptsOwnHostOverHTTPSAnyCase() throws {
        try PageURLPolicy.validate(URL(string: "https://Canvas.Northfield.example/api/v1/courses?page=2")!,
                                   allowedHosts: ["canvas.northfield.example"])
    }

    @Test(arguments: [
        ("http://canvas.northfield.example/p2", PageURLError.notHTTPS),
        ("https://canvas.northfield.example.evil.test/p2", .foreignHost),
        ("https://evil.test/p2", .foreignHost),
        ("https://canvas.northfield.example:8443/p2", .foreignHost),
        ("https://user:pw@canvas.northfield.example/p2", .hasCredentials),
    ])
    func rejectsUnsafeNextURLs(_ url: String, _ expected: PageURLError) {
        #expect(throws: expected) {
            try PageURLPolicy.validate(URL(string: url)!, allowedHosts: ["canvas.northfield.example"])
        }
    }
}
