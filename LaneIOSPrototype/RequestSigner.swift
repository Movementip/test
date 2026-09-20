import Foundation
import CryptoKit
import Security

protocol LaneRequestSigner: Sendable {
    func sign(_ request: URLRequest, body: Data?) throws -> URLRequest
}

struct UnsignedLaneRequestSigner: LaneRequestSigner {
    func sign(_ request: URLRequest, body: Data?) throws -> URLRequest {
        request
    }
}

struct APIKeyLaneRequestSigner: LaneRequestSigner {
    let headerName: String
    let token: String

    func sign(_ request: URLRequest, body: Data?) throws -> URLRequest {
        var signed = request
        let cleanHeader = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        if !cleanHeader.isEmpty && !cleanToken.isEmpty {
            signed.setValue(cleanToken, forHTTPHeaderField: cleanHeader)
        }

        return signed
    }
}

/// Swift port of the request-signing path used by Lane Android 1.4.7.
///
/// The native Android implementation builds three request headers:
/// - X-Core-Token
/// - X-Client-Meta
/// - X-Request-Trace-Id
///
/// GET requests are reproduced byte-for-byte at the algorithm level. The
/// non-empty body transform used for mutation requests is handled separately;
/// the current signer intentionally leaves an already-built body unchanged.
struct BNITLaneRequestSigner: LaneRequestSigner {
    private static let signingKey = Data("SqperSzvbntKmv_CbnngeThis_12303!".utf8)

    private static let customBase64Alphabet: [UInt8] =
        Array("zxcvbnmasdfghjklqwertyuiop1234567890-_QWERTYUIOPASDFGHJKLZXCVBNM".utf8)

    func sign(_ request: URLRequest, body: Data?) throws -> URLRequest {
        guard let url = request.url else {
            return request
        }

        var signed = request

        let method = (request.httpMethod ?? "GET").uppercased()
        let path = Self.encodedPath(of: url)
        let query = Self.canonicalQuery(of: url)
        let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000.0))
        let nonce = Self.hex(try Self.randomBytes(count: 16))

        // These are valid fallback branches present in the Android native code.
        // The server receives the same values inside the encrypted metadata and
        // verifies the request against them.
        let bootID = "UNKNOWN_BOOT"
        let apkInode = "NO_APK_INODE"

        let requestBody = body ?? Data()

        var canonical = Data()
        Self.append(method, to: &canonical)
        canonical.append(0x3A)
        Self.append(path, to: &canonical)
        canonical.append(0x3A)
        Self.append(query, to: &canonical)
        canonical.append(0x3A)
        Self.append(timestamp, to: &canonical)
        canonical.append(0x3A)
        Self.append(nonce, to: &canonical)
        canonical.append(0x3A)

        // Android BNIT applies an additional transform for non-empty bodies.
        // GET/auth/search requests have an empty body and therefore follow this
        // exact path. Keeping the bytes here preserves compatibility for empty
        // body requests while body signing is implemented independently.
        canonical.append(requestBody)

        canonical.append(0x3A)
        Self.append(bootID, to: &canonical)
        canonical.append(0x3A)
        Self.append(apkInode, to: &canonical)

        let key = SymmetricKey(data: Self.signingKey)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: canonical, using: key)
        let hmacHex = authenticationCode.map { String(format: "%02x", $0) }.joined()

        let metadata = "\(hmacHex)|\(timestamp)|\(nonce)|\(bootID)|\(apkInode)|1"
        let encryptedMetadata = try Self.encryptCoreToken(Data(metadata.utf8))
        let coreToken = Self.customBase64(encryptedMetadata)

        let clientMeta = Self.customBase64(try Self.randomBytes(count: 24))
        let traceID = Self.traceID(from: try Self.randomBytes(count: 16))

        signed.setValue("1", forHTTPHeaderField: "X-Accept-Red")
        signed.setValue(coreToken, forHTTPHeaderField: "X-Core-Token")
        signed.setValue(clientMeta, forHTTPHeaderField: "X-Client-Meta")
        signed.setValue(traceID, forHTTPHeaderField: "X-Request-Trace-Id")

        return signed
    }

    private static func encodedPath(of url: URL) -> String {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           !components.percentEncodedPath.isEmpty {
            return components.percentEncodedPath
        }
        return url.path.isEmpty ? "/" : url.path
    }

    /// Mirrors the Android interceptor: distinct query parameter names, sorted,
    /// then rendered as name=value and joined by '&'.
    private static func canonicalQuery(of url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              !items.isEmpty else {
            return ""
        }

        var firstValueByName: [String: String] = [:]
        for item in items where firstValueByName[item.name] == nil {
            firstValueByName[item.name] = item.value ?? ""
        }

        return firstValueByName.keys.sorted().map { name in
            "\(name)=\(firstValueByName[name] ?? "")"
        }.joined(separator: "&")
    }

    private static func encryptCoreToken(_ plaintext: Data) throws -> Data {
        let salt = try randomBytes(count: 4)
        let key = [UInt8](signingKey)
        let saltBytes = [UInt8](salt)

        var state = Array(0...255).map(UInt8.init)
        var j = 0

        for i in 0..<256 {
            j = (j
                 + Int(state[i])
                 + Int(key[i & 31])
                 + Int(saltBytes[i & 3])) & 0xFF
            state.swapAt(i, j)
        }

        var output = Data(salt)
        var i = 0
        j = 0
        var previous: UInt8 = 0x5A

        for plain in plaintext {
            i = (i + 1) & 0xFF

            let oldSi = state[i]
            j = (j + Int(oldSi)) & 0xFF
            let oldSj = state[j]

            state[i] = oldSj
            state[j] = oldSi

            let index = (Int(oldSi) + Int(oldSj)) & 0xFF
            let mixedIndex = index ^ Int(previous)

            var cipher = plain ^ state[mixedIndex]
            cipher = rotateLeft8(cipher, by: 3)
            cipher = cipher &+ previous
            previous = cipher

            output.append(cipher)
        }

        return output
    }

    private static func rotateLeft8(_ value: UInt8, by amount: UInt8) -> UInt8 {
        let shift = amount & 7
        if shift == 0 { return value }
        return (value << shift) | (value >> (8 - shift))
    }

    private static func customBase64(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var output = [UInt8]()
        output.reserveCapacity(((bytes.count + 2) / 3) * 4)

        var index = 0
        while index < bytes.count {
            let b0 = bytes[index]
            let hasB1 = index + 1 < bytes.count
            let hasB2 = index + 2 < bytes.count
            let b1: UInt8 = hasB1 ? bytes[index + 1] : 0
            let b2: UInt8 = hasB2 ? bytes[index + 2] : 0

            output.append(customBase64Alphabet[Int(b0 >> 2)])
            output.append(customBase64Alphabet[Int(((b0 & 0x03) << 4) | (b1 >> 4))])

            if hasB1 {
                output.append(customBase64Alphabet[Int(((b1 & 0x0F) << 2) | (b2 >> 6))])
            } else {
                output.append(UInt8(ascii: "."))
            }

            if hasB2 {
                output.append(customBase64Alphabet[Int(b2 & 0x3F)])
            } else {
                output.append(UInt8(ascii: "."))
            }

            index += 3
        }

        return String(bytes: output, encoding: .utf8) ?? ""
    }

    private static func traceID(from bytes: Data) -> String {
        let hexString = hex(bytes)
        guard hexString.count >= 32 else { return hexString }

        let a = hexString.index(hexString.startIndex, offsetBy: 8)
        let b = hexString.index(a, offsetBy: 4)
        let c = hexString.index(b, offsetBy: 4)
        let d = hexString.index(c, offsetBy: 4)

        return [
            String(hexString[..<a]),
            String(hexString[a..<b]),
            String(hexString[b..<c]),
            String(hexString[c..<d]),
            String(hexString[d...])
        ].joined(separator: "-")
    }

    private static func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Secure random generation failed"]
            )
        }
        return Data(bytes)
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func append(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }
}

enum LaneBackendMode: String, CaseIterable, Identifiable {
    case official = "official"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .official: return "Official Lane"
        case .custom: return "Custom backend"
        }
    }
}

struct LaneSigningConfiguration: Equatable {
    var mode: LaneBackendMode
    var apiKeyHeader: String
    var apiKey: String

    static let official = LaneSigningConfiguration(
        mode: .official,
        apiKeyHeader: "",
        apiKey: ""
    )

    var signer: any LaneRequestSigner {
        switch mode {
        case .official:
            return BNITLaneRequestSigner()
        case .custom:
            return APIKeyLaneRequestSigner(
                headerName: apiKeyHeader,
                token: apiKey
            )
        }
    }
}
