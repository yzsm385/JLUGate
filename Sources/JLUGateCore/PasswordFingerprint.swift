import Foundation
import CryptoKit

/// 密码指纹：只用来**核对"这次输入的是不是和上次同一串"**，不能反推出密码。
///
/// 为什么需要它：服务器只回 `0x15`（凭据被拒），客户端无法知道是
/// "密码本身不对" 还是 "输入被某种方式改了"（输入法全角、末尾空格、粘贴多了字符）。
/// 记一个 8 位指纹 + 长度，两次输入一对比就能分辨。
public enum PasswordFingerprint {
    public static func of(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(8).description
    }

    /// 长度 + 指纹（日志里只用这个，绝不写密码本身）
    public static func describe(_ password: String) -> String {
        "\(password.count) 字符 / 指纹 \(of(password))"
    }
}
