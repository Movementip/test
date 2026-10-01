import Foundation

struct ProbeHTTP {
    let status: Int
    let data: Data
    let response: HTTPURLResponse
    let elapsedMS: Int
}

@main
enum LaneProbe {
    static let session = URLSession(configuration: .ephemeral)

    static func timeProbe(host: String) async -> (offset: Int64, text: String)? {
        guard let url = URL(string: host + "/time") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 6
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let start = Date()
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { return nil }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let timestamp = (object?["timestamp"] as? NSNumber)?.int64Value ?? 0
            let offset = timestamp - Int64(Date().timeIntervalSince1970 * 1000)
            return (offset, "\(http.statusCode)/\(ms)ms")
        } catch {
            return (0, "ERR/\(error.localizedDescription)")
        }
    }

    static func makeRequest(
        host: String,
        path: String,
        method: String = "GET",
        token: String,
        ldi: String,
        offset: Int64,
        query: [URLQueryItem] = [],
        json: Any? = nil
    ) throws -> URLRequest {
        guard var parts = URLComponents(string: host + path) else {
            throw URLError(.badURL)
        }
        if !query.isEmpty { parts.queryItems = query }
        guard let url = parts.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        request.setValue(ldi, forHTTPHeaderField: "LDI")
        request.setValue("UTC", forHTTPHeaderField: "TZ")
        request.setValue("207", forHTTPHeaderField: "X-App-Version")
        request.setValue("android", forHTTPHeaderField: "X-Platform")
        request.setValue("dark", forHTTPHeaderField: "X-Theme")
        request.setValue("LaneMusic/1.0 (Android; Mobile)", forHTTPHeaderField: "User-Agent")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let signer = BNITLaneRequestSigner(timeOffsetMilliseconds: offset)
        return try signer.sign(request, body: request.httpBody)
    }

    static func send(_ request: URLRequest) async throws -> ProbeHTTP {
        let start = Date()
        let (raw, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        var data = raw
        if http.value(forHTTPHeaderField: "X-Core-Red") == "1",
           let nonce = http.value(forHTTPHeaderField: "X-Resp-Nonce"),
           !nonce.isEmpty {
            data = BNITLaneRequestSigner.decryptResponse(raw, responseNonce: nonce)
            if http.value(forHTTPHeaderField: "X-Core-Compressed") == "1" {
                data = try LaneGzip.decompress(data)
            }
        }

        return ProbeHTTP(
            status: http.statusCode,
            data: data,
            response: http,
            elapsedMS: Int(Date().timeIntervalSince(start) * 1000)
        )
    }

    static func errorCode(_ data: Data) -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return ""
        }
        if let code = object["code"] as? String { return code }
        if let message = object["message"] as? String { return message }
        return ""
    }

    static func firstTrackID(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            for key in ["songId", "trackId"] {
                if let value = dict[key] as? String, !value.isEmpty { return value }
            }
            if let values = dict["playlistTracksIds"] as? [String], let first = values.first, !first.isEmpty {
                return first
            }
            for value in dict.values {
                if let found = firstTrackID(in: value) { return found }
            }
        } else if let list = object as? [Any] {
            for value in list {
                if let found = firstTrackID(in: value) { return found }
            }
        }
        return nil
    }

    static func probeTracks(
        host: String,
        token: String,
        ldi: String,
        offset: Int64,
        trackID: String,
        body: Any,
        label: String
    ) async {
        do {
            let req = try makeRequest(
                host: host,
                path: "/user/tracks",
                method: "POST",
                token: token,
                ldi: ldi,
                offset: offset,
                query: [URLQueryItem(name: "prefetch", value: "false")],
                json: body
            )
            let res = try await send(req)
            let obj = try? JSONSerialization.jsonObject(with: res.data)
            let count = (obj as? [Any])?.count ?? -1
            print("  user/tracks \(label): HTTP \(res.status) \(res.elapsedMS)ms count=\(count) code=\(errorCode(res.data))")
        } catch {
            print("  user/tracks \(label): ERROR \(error.localizedDescription)")
        }
    }

    static func main() async {
        let hosts = ["https://laneapi.com", "https://ru.laneapi.com"]
        let env = ProcessInfo.processInfo.environment
        let token = env["LANE_TEST_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ldi = env["LANE_TEST_LDI"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        print("Lane server probe (no secrets are printed)")
        var offsets: [String: Int64] = [:]

        for host in hosts {
            if let probe = await timeProbe(host: host) {
                offsets[host] = probe.offset
                print("\(host) /time: \(probe.text)")
            } else {
                print("\(host) /time: unavailable")
            }
        }

        guard !token.isEmpty, !ldi.isEmpty else {
            print("Authenticated checks skipped: configure LANE_TEST_TOKEN and LANE_TEST_LDI repository secrets.")
            return
        }

        for host in hosts {
            print("\nAuthenticated: \(host)")
            let offset = offsets[host] ?? 0

            do {
                let req = try makeRequest(
                    host: host,
                    path: "/account",
                    token: token,
                    ldi: ldi,
                    offset: offset,
                    query: [URLQueryItem(name: "deviceLanguage", value: "en")]
                )
                let res = try await send(req)
                print("  account: HTTP \(res.status) \(res.elapsedMS)ms code=\(errorCode(res.data))")
            } catch {
                print("  account: ERROR \(error.localizedDescription)")
            }

            var trackID: String?
            do {
                let req = try makeRequest(
                    host: host,
                    path: "/user/recent",
                    token: token,
                    ldi: ldi,
                    offset: offset
                )
                let res = try await send(req)
                print("  recent: HTTP \(res.status) \(res.elapsedMS)ms code=\(errorCode(res.data))")
                if let object = try? JSONSerialization.jsonObject(with: res.data) {
                    trackID = firstTrackID(in: object)
                }
            } catch {
                print("  recent: ERROR \(error.localizedDescription)")
            }

            do {
                let req = try makeRequest(
                    host: host,
                    path: "/user/playlists",
                    token: token,
                    ldi: ldi,
                    offset: offset
                )
                let res = try await send(req)
                let object = try? JSONSerialization.jsonObject(with: res.data)
                let count = (object as? [Any])?.count ?? -1
                print("  playlists: HTTP \(res.status) \(res.elapsedMS)ms count=\(count) code=\(errorCode(res.data))")
                if trackID == nil, let object {
                    trackID = firstTrackID(in: object)
                }
            } catch {
                print("  playlists: ERROR \(error.localizedDescription)")
            }

            if let trackID {
                await probeTracks(
                    host: host,
                    token: token,
                    ldi: ldi,
                    offset: offset,
                    trackID: trackID,
                    body: ["trackIds": [trackID]],
                    label: "object"
                )
                await probeTracks(
                    host: host,
                    token: token,
                    ldi: ldi,
                    offset: offset,
                    trackID: trackID,
                    body: [trackID],
                    label: "raw"
                )
            } else {
                print("  user/tracks: SKIP no sample track ID")
            }
        }
    }
}
