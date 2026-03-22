import Foundation

actor LRCLibService {
    static let shared = LRCLibService()

    private let baseURL = "https://lrclib.net/api"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    func fetchLyrics(title: String, artist: String?, duration: Double) async -> LyricsFile? {
        let cleanTitle = Self.cleanQuery(title)
        let cleanArtist = artist.map { Self.cleanQuery($0) }

        if let cleanArtist, !cleanArtist.isEmpty {
            if let result = await getExact(title: cleanTitle, artist: cleanArtist, duration: duration) {
                return result
            }
            if let result = await getExact(title: cleanArtist, artist: cleanTitle, duration: duration) {
                return result
            }
        }

        if let result = await search(title: cleanTitle, artist: cleanArtist, duration: duration) {
            return result
        }

        if let cleanArtist, !cleanArtist.isEmpty {
            return await search(title: cleanArtist, artist: cleanTitle, duration: duration)
        }

        return nil
    }

    private static func cleanQuery(_ text: String) -> String {
        var result = text
        let noise = try! NSRegularExpression(
            pattern: "\\((?:con letra|official(?:\\s+music)?\\s+video|video oficial|lyric(?:s)?\\s*(?:video)?|audio|live|en vivo|hd|hq|remaster(?:ed)?)\\)",
            options: .caseInsensitive
        )
        result = noise.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        result = result.trimmingCharacters(in: .whitespaces)
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    private func getExact(title: String, artist: String, duration: Double) async -> LyricsFile? {
        var components = URLComponents(string: "\(baseURL)/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "duration", value: String(Int(duration))),
        ]
        guard let url = components.url else { return nil }

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }

        return parseLRCLibResponse(data)
    }

    private func search(title: String, artist: String?, duration: Double) async -> LyricsFile? {
        var query = title
        if let artist, !artist.isEmpty {
            query = "\(artist) \(title)"
        }

        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
        ]
        guard let url = components.url else { return nil }

        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return nil
        }

        guard let results = try? JSONDecoder().decode([LRCLibResult].self, from: data) else {
            return nil
        }

        let best = results
            .filter { !$0.instrumental && $0.syncedLyrics != nil }
            .min(by: { abs($0.duration - duration) < abs($1.duration - duration) })

        guard let best else { return nil }
        return parseSyncedLyrics(best.syncedLyrics!)
    }

    private func parseLRCLibResponse(_ data: Data) -> LyricsFile? {
        guard let result = try? JSONDecoder().decode(LRCLibResult.self, from: data) else {
            return nil
        }
        if result.instrumental { return nil }
        guard let synced = result.syncedLyrics else { return nil }
        return parseSyncedLyrics(synced)
    }

    private func parseSyncedLyrics(_ lrc: String) -> LyricsFile {
        let lines = lrc.components(separatedBy: "\n")
        var segments: [LyricLine] = []

        let pattern = /\[(\d{2}):(\d{2})\.(\d{2,3})\]\s?(.*)/

        for line in lines {
            if let match = line.firstMatch(of: pattern) {
                let minutes = Double(match.1) ?? 0
                let seconds = Double(match.2) ?? 0
                let centis = match.3
                let fraction: Double
                if centis.count == 3 {
                    fraction = (Double(centis) ?? 0) / 1000.0
                } else {
                    fraction = (Double(centis) ?? 0) / 100.0
                }
                let timestamp = minutes * 60 + seconds + fraction
                let text = String(match.4).trimmingCharacters(in: .whitespaces)

                if text.isEmpty {
                    segments.append(LyricLine(start: timestamp, end: timestamp, text: "", words: []))
                } else {
                    let words = text.split(separator: " ", omittingEmptySubsequences: true).map { word in
                        LyricWord(word: String(word), start: timestamp, end: timestamp)
                    }
                    segments.append(LyricLine(start: timestamp, end: timestamp, text: text, words: words))
                }
            }
        }

        for i in 0..<segments.count {
            if i + 1 < segments.count {
                let nextStart = segments[i + 1].start
                if !segments[i].words.isEmpty {
                    let wordDuration = (nextStart - segments[i].start) / Double(segments[i].words.count)
                    for j in 0..<segments[i].words.count {
                        segments[i].words[j] = LyricWord(
                            word: segments[i].words[j].word,
                            start: segments[i].start + wordDuration * Double(j),
                            end: segments[i].start + wordDuration * Double(j + 1)
                        )
                    }
                }
                segments[i] = LyricLine(
                    start: segments[i].start,
                    end: nextStart,
                    text: segments[i].text,
                    words: segments[i].words
                )
            }
        }

        return LyricsFile(language: "und", segments: segments)
    }
}

private struct LRCLibResult: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
}
