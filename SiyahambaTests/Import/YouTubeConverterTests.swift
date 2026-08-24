import Foundation
import Testing
@testable import Siyahamba

struct YouTubeConverterTests {
    @Test(arguments: [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ"
    ])
    func normalizesIndividualVideoURLs(rawURL: String) throws {
        let parsed = try YouTubeURL(url: #require(URL(string: rawURL)))

        #expect(parsed.videoID == "dQw4w9WgXcQ")
        #expect(parsed.canonicalURL.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    @Test func rejectsPlaylist() throws {
        let url = try #require(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123"))
        #expect(throws: YouTubeConverterError.playlistNotSupported) {
            try YouTubeURL(url: url)
        }
    }

    @Test(arguments: ["https://example.com/watch?v=dQw4w9WgXcQ", "https://youtube.com/channel/test"])
    func rejectsUnsupportedURLs(rawURL: String) throws {
        #expect(throws: YouTubeConverterError.invalidURL) {
            try YouTubeURL(url: #require(URL(string: rawURL)))
        }
    }
}
