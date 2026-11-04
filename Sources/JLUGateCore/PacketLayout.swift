import Foundation

/// **唯一**允许出现魔法数字/偏移的地方（PLAN §5.1）。
///
/// 除特别注明，所有多字节整数一律**大端**（与抓包字节序一致）：
/// 抓包里序号 `1d 63`、长度域 `00 1f`、`28 00`（=40）都是高字节在前。
/// 例外在字段注释里逐条写明（例如保活应答的统计量是小端）。
///
/// 证据来源：`docs/captures/login.pcap`（2026-11-02 20:29:17–20:31:40）逐字节对齐。
/// CHECKLIST §5.1 的偏移表有若干 off-by-N（例如 0x059/0x066 段），
/// 这里以**抓包字节**为准，并在 `docs/progress.md` 里列出全部修订。
public enum PacketLayout {

    // MARK: 常量

    public static let defaultServer = IPv4Address("10.100.61.3")!
    public static let serverPort: UInt16 = 61440
    public static let localPort: UInt16 = 61440

    /// 客户端版本串，登录包 0x0C0，**必须照抄**。
    public static let clientVersion = "25.6.0"
    /// 登录包 0x0B6 的魔数（注意大小写：这里是 `DrCOM`）。
    public static let loginMagic: [UInt8] = Array("DrCOM".utf8)
    /// 保活包里的魔数（`Drco`，小写 o）。
    public static let keepAliveMagic: [UInt8] = Array("Drco".utf8)
    /// 40 个 ASCII 字符的静态令牌，两次登录完全一致，直接当常量。
    public static let staticToken = "56c68373463f4cd5b73dd3ac5e3673000a5fdd7e"

    // MARK: 帧长度表（CHECKLIST §2 / protocol-findings §1）

    public enum Length {
        public static let challenge = 20
        public static let challengeReply = 76
        public static let accountProbe = 80
        public static let genericAck = 25
        public static let login = 342
        public static let loginSuccess = 45
        public static let loginFailure = 37
        public static let keepAliveARequest = 38
        public static let keepAliveAReply = 72
        public static let keepAliveB = 40
    }

    // MARK: Challenge（C→S，20 字节）

    public enum Challenge {
        public static let kind: UInt8 = 0x01
        public static let firstSubtype: UInt8 = 0x03
        public static let flag: UInt8 = 0x31
        public static let serialOffset = 0x02          // u16 BE
        public static let subtypeOffset = 0x01
        public static let flagOffset = 0x04
    }

    // MARK: Challenge 应答（S→C，76 字节）

    public enum ChallengeReply {
        public static let kind: UInt8 = 0x02
        /// 登录摘要要用的 4 字节 salt。
        public static let saltOffset = 0x04
        public static let saltLength = 4
        /// 服务器回显的客户端 IP。
        public static let clientIPOffset = 0x14
        /// 回显序号。
        public static let serialOffset = 0x02
        public static let clientIPLength = 4
        /// 服务器分配的会话别名（小端）；保活 B 的 0x06–0x07 与保活 A 应答统计的第 1 个字都用它
        /// （抓包 `dc 02` = 732）。
        public static let sessionIDOffset = 0x26
    }

    // MARK: 登录包（C→S，342 字节）

    public enum Login {
        // 依据 jlu-drcom-ng v2.0.0（社区维护的 JLU 实现）与 JKDrcom 交叉验证：
        // 基础长度 338，密码段从 312 开始，长度随密码长度增长。
        public static let baseLength = 338
        public static let passwordSectionOffset = 312

        public static let kind: UInt8 = 0x03
        public static let subtype: UInt8 = 0x01

        public static let digestAOffset = 0x004
        public static let digestALength = 16
        public static let accountOffset = 0x014
        public static let accountLength = 36

        public static let controlOffset = 0x038       // 0x20
        public static let adapterOffset = 0x039       // 0x03
        public static let xorOffset = 0x03A
        public static let xorLength = 6
        public static let md5bOffset = 0x040
        public static let md5bLength = 16

        public static let ipCountOffset = 0x050       // 0x01
        public static let md5cOffset = 0x061
        public static let md5cLength = 8
        public static let md5cProbe: [UInt8] = [0x14, 0x00, 0x07, 0x0B]
        public static let ipDogOffset = 0x069         // 0x01

        /// 0x6E..0x78 = "LIYUANYUAN"（官方客户端的固定串）
        public static let vendorOffset = 0x06E
        public static let vendor = "LIYUANYUAN"
        /// 主机名上限（当前版本的登录包不携带主机名，保留常量供截断逻辑使用）
        public static let hostnameLength = 26

        public static let dnsOffset = 0x08E
        public static let dnsValue: [UInt8] = [10, 10, 10, 10]

        public static let osFieldOffset = 0x0A2
        public static let osFields: [(offset: Int, value: UInt32)] = [
            (0x0A2, 0x94), (0x0A6, 6), (0x0AA, 2), (0x0AE, 0x23F0), (0x0B2, 2),
        ]

        /// 0xB6..0xBF：`DrCOM\0\xCF\x07\x68`
        public static let hostBlobOffset = 0x0B6
        public static let hostBlob: [UInt8] = [0x44, 0x72, 0x43, 0x4F, 0x4D, 0x00, 0xCF, 0x07, 0x68]

        /// 0xF6..0x11E：40 字节服务包标识
        public static let servicePackOffset = 0x0F6
        public static let servicePack = "3dc79f5212e8170acfa9ec95f1d74916542be7b1"

        public static let tailMarkerOffset = 310
        public static let tailMarker: UInt8 = 0x68
        public static let passwordLengthOffset = 313
        public static let rorOffset = 314
        public static let separatorAfterROR: [UInt8] = [0x02, 0x0C]
        public static let checksumPlaceholder: [UInt8] = [0x01, 0x26, 0x07, 0x11, 0x00, 0x00]
        public static let macOffsetAfterROR = 8
        public static let tailFoot: [UInt8] = [0x60, 0xA2]

        /// 登录包长度 = 338 + extra（<=8 字符不加长）。
        public static func padding(passwordLength: Int) -> (extra: Int, rorPadding: Int) {
            guard passwordLength > 8 else {
                return (0, 8 - passwordLength)          // 短密码：尾部补到 8 字节再放脚标
            }
            let rorPadding = passwordLength == 16 ? 0 : passwordLength / 4
            return (28 + passwordLength - 8 + rorPadding, rorPadding)
        }

        public static func length(passwordLength: Int) -> Int {
            baseLength + padding(passwordLength: passwordLength).extra
        }
    }

    public enum LoginResult {
        public static let successKind: UInt8 = 0x04
        public static let failureKind: UInt8 = 0x05
        public static let subtype: UInt8 = 0x00
        /// 失败原因串起点，NUL 结尾，原样展示。
        /// CHECKLIST 写作 0x18，但抓包实测 `ldap auth error` 从 **0x14** 开始（前面的 0x14 字节是状态位）。
        public static let failureReasonOffset = 0x14
        /// 成功包里 `Drco` 块的起点（后续 16 字节结构与保活 A 一致）。
        public static let successTailOffset = 0x17
    }

    /// `Drco` 块：`Drco`(4) + 服务器 IP(4) + 不透明 2 + 客户端 IP(4) + 不透明 2。
    /// 登录成功包（起点 0x17）与保活 A 请求（起点 0x14）都是用这套结构。
    public enum DrcoBlock {
        public static let magicOffset = 0
        public static let magicLength = 4
        public static let serverIPOffset = 4
        public static let opaque1Offset = 8
        public static let opaque1Length = 2
        public static let clientIPOffset = 10
        public static let clientIPLength = 4
        public static let opaque2Offset = 14
        public static let opaque2Length = 2
        public static let length = 16
    }

    // MARK: 保活 A（38 → 72）

    public enum KeepAliveA {
        public static let kind: UInt8 = 0xFF
        /// 0x01–0x10：**登录摘要 A**（实测与登录包 0x004 的 16 字节完全相同）。
        public static let digestOffset = 0x01
        public static let digestLength = 16
        /// 0x11–0x13 恒为 0。
        public static let drcoBlockOffset = 0x14
        /// 0x24–0x25：会话号（大端），等于本次登录的会话号。
        /// 会话号：**小端 u16**，语义是随时间递增的秒计数。
        /// 抓包字节 `40 63`→`53 63`→…→`a3 63` 即小端值 0x6340→0x6353→…→0x63a3，
        /// 每次 A 型保活（约 20s）涨 ~20 —— 所以它是个时钟，而不是随机 ID。
        public static let sessionOffset = 0x24
        public static let sessionLength = 2

        // 应答（72）
        public static let replyKind: UInt8 = 0x07
        public static let replySubtype: UInt8 = 0x01
        public static let replySessionOffset = 0x06
        /// 0x1C 起 6 个小端 u32：第 1 个恒等于 `0xdc02` 会话别名，第 2 个随秒递增，
        /// 其余未解（CHECKLIST 写作"0x20 起"，实测起点 0x1C）。
        public static let statsOffset = 0x1C
        public static let statsCount = 6
    }

    // MARK: 保活 B（40 → 40）

    public enum KeepAliveB {
        public static let kind: UInt8 = 0x07
        public static let roundOffset = 0x01
        /// 长度域：字节是 `28 00`，**小端** 40（CHECKLIST §6.2 的写法是对的，别按大端读成 10240）。
        public static let lengthFieldOffset = 0x02
        public static let lengthFieldValue: UInt16 = 40
        public static let flagOffset = 0x04          // `0b`
        public static let flagValue: UInt8 = 0x0B
        public static let seqOffset = 0x05           // 请求/应答共用自增计数
        public static let sessionOffset = 0x06       // `dc 02` = 小端 732
        public static let timestampOffset = 0x08     // 小端 u32
        /// 4 字节，镜像服务器上一次的取值，会话内稳定（抓包实测在 0x10，CHECKLIST 写作 0x14）。
        public static let mirrorOffset = 0x10
        /// 4 字节，每包不同（只在"一对里的第 2 包"出现，第 1 包为 0）。
        public static let checkOffset = 0x18
        public static let clientIPOffset = 0x1C      // 一对中的第 2 包装 IP，第 1 包为 0
    }

    // MARK: 摘要

    /// `digestA = MD5(0x03 ‖ 0x01 ‖ salt(4) ‖ password_utf8)`（已用真实样本逐字节验证）。
    public static let digestPrefix: [UInt8] = [0x03, 0x01]
}
