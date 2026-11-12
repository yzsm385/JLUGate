import Foundation

/// 最小 TLS ClientHello 构造器。
///
/// 为什么手写而不用 OpenSSL / Network.framework：
/// 1. 探针只需要「对端有没有在 TLS 层回应」，不需要完成握手、不需要证书；
/// 2. `PLAN.md` §8.2 禁止用 `URLSession`（无法绑出口网卡，TUN 下被劫持）；
/// 3. 引入 TLS 库会给一个只做探测的场景增加不必要的依赖面。
///
/// 生成的是 TLS 1.2 ClientHello（record version 0x0301，handshake 里最高支持 1.2），
/// 带 SNI 扩展。这是 2026-11-11 排查时用 `openssl s_client` 验证过的等价形态：
/// 带 SNI 和不带 SNI 都会被切断，所以这里带 SNI 是为了更贴近真实浏览器行为。
enum TLSClientHello {
    /// 生成发给 `host` 的 ClientHello 字节序列。
    ///
    /// - Parameter host: SNI 用的域名。传空串则不发送 SNI 扩展。
    static func make(host: String) -> [UInt8] {
        var extensions: [UInt8] = []

        // SNI（type 0x0000）
        if !host.isEmpty {
            let name = Array(host.utf8)
            var sni: [UInt8] = []
            // server_name_list 长度（2 字节）= 1（type）+ 2（length）+ name
            let listLength = name.count + 3
            sni += u16(UInt16(listLength))
            sni += [0x00]                    // name_type: host_name
            sni += u16(UInt16(name.count))
            sni += name
            extensions += u16(0x0000)
            extensions += u16(UInt16(sni.count))
            extensions += sni
        }

        // supported_groups（type 0x000a）：x25519 + secp256r1
        extensions += u16(0x000a)
        extensions += u16(6)
        extensions += u16(4)
        extensions += u16(0x001d)
        extensions += u16(0x0017)

        // signature_algorithms（type 0x000d）：rsa_pkcs1_sha256 + ecdsa_secp256r1_sha256
        extensions += u16(0x000d)
        extensions += u16(6)
        extensions += u16(4)
        extensions += u16(0x0401)
        extensions += u16(0x0403)

        // 组装 ClientHello body
        var body: [UInt8] = []
        body += u16(0x0303)                  // client_version: TLS 1.2
        body += Array(repeating: 0x00, count: 32)   // random（内容无关，只要长度对）
        body += [0x00]                       // session_id 长度 = 0
        body += u16(2)                       // cipher_suites 长度
        body += u16(0x002f)                  // TLS_RSA_WITH_AES_128_CBC_SHA
        body += [0x01, 0x00]                 // compression: 1 种，null
        body += u16(UInt16(extensions.count))
        body += extensions

        // handshake 头：type(1) + length(3)
        var handshake: [UInt8] = [0x01]
        handshake += u24(UInt32(body.count))
        handshake += body

        // record 头：type(1)=handshake + version(2) + length(2)
        var record: [UInt8] = [0x16]
        record += u16(0x0301)
        record += u16(UInt16(handshake.count))
        record += handshake
        return record
    }

    private static func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xff)]
    }

    private static func u24(_ value: UInt32) -> [UInt8] {
        [UInt8((value >> 16) & 0xff), UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
    }
}
