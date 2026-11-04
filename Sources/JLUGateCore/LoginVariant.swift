import Foundation

/// 登录报文有两个在用的版本：
/// - `.current`：jlu-drcom-ng v2.0.0（社区维护，当前服务端接受的版本）
/// - `.legacy`：本仓库 2026-11-02 抓到的官方客户端版本
///
/// 服务端在"版本不兼容"时会回错误码 `0x15`，引擎据此在两个版本间各试一次。
public enum LoginVariant: String, Sendable, CaseIterable, Equatable {
    case current
    case legacy
}
