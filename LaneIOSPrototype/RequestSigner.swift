import Foundation

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
            return UnsignedLaneRequestSigner()
        case .custom:
            return APIKeyLaneRequestSigner(
                headerName: apiKeyHeader,
                token: apiKey
            )
        }
    }
}
