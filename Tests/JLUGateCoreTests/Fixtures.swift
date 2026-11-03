import Foundation
import Testing
@testable import JLUGateCore

/// 夹具加载：从仓库根的 `Fixtures/` 读，路径由本文件的 `#filePath` 推导，
/// 这样 `swift test` 在任意工作目录下都能找到。
enum Fixtures {
    static let root: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // JLUGateCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // 仓库根
        .appendingPathComponent("Fixtures")

    static func hex(_ name: String) throws -> [UInt8] {
        let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
        return try bytes(hexString: text)
    }

    static func bytes(hexString: String) throws -> [UInt8] {
        let cleaned = hexString.filter { $0.isHexDigit }
        guard cleaned.count % 2 == 0 else { throw FixtureError.oddLength }
        var result: [UInt8] = []
        result.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let value = UInt8(cleaned[index..<next], radix: 16) else {
                throw FixtureError.badHex
            }
            result.append(value)
            index = next
        }
        return result
    }

    /// 抓包会话的全部 UDP 载荷（c2s / s2c）。
    struct Session {
        let frames: [(dir: String, payload: [UInt8])]
        let account: String
        let password: String
        let hostname: String
        let mac: MACAddress
        let linkLocal: IPv4Address
        let clientIP: IPv4Address

        func first(_ dir: String, length: Int) -> [UInt8]? {
            frames.first { $0.dir == dir && $0.payload.count == length }?.payload
        }

        func all(_ dir: String, length: Int) -> [[UInt8]] {
            frames.filter { $0.dir == dir && $0.payload.count == length }.map(\.payload)
        }
    }

    static func session() throws -> Session {
        let url = root.appendingPathComponent("session_sanitized.json")
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawFrames = json["frames"] as? [[String: Any]] else {
            throw FixtureError.badJSON
        }
        var frames: [(String, [UInt8])] = []
        for frame in rawFrames {
            guard let dir = frame["dir"] as? String,
                  let hex = frame["hex"] as? String else { throw FixtureError.badJSON }
            let bytes = try bytes(hexString: hex)
            if let declared = frame["len"] as? Int, declared != bytes.count {
                throw FixtureError.badJSON
            }
            frames.append((dir, bytes))
        }
        return Session(
            frames: frames,
            account: json["account"] as? String ?? "",
            password: json["password"] as? String ?? "",
            hostname: json["hostname"] as? String ?? "",
            mac: MACAddress(json["mac"] as? String ?? "") ?? MACAddress(bytes: [0, 0, 0, 0, 0, 0])!,
            linkLocal: IPv4Address(json["linkLocal"] as? String ?? "") ?? .zero,
            clientIP: IPv4Address(json["local"] as? String ?? "") ?? .zero)
    }

    enum FixtureError: Error {
        case oddLength
        case badHex
        case badJSON
    }
}

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}
