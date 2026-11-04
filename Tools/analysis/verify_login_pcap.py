#!/usr/bin/env python3
"""从 Dr.Com 抓包里把「挑战应答 → 登录包」配对，验证摘要公式。

用法：
    python3 Tools/analysis/verify_login_pcap.py ~/Desktop/login-full.pcap --password '你的密码'

它会做三件事：
1. 解析 pcap（以太网 / Linux SLL / 原始 IP，UDP 61440）；
2. 按时间顺序把 76 字节挑战应答与 342 字节登录包配对；
3. 用 MD5(0x03‖0x01‖salt‖password) 复算，逐条报告「匹配 / 不匹配」，
   并打印不匹配时的 salt、摘要、以及对应登录包里的账号与 MAC。

输出可安全分享（不含密码；账号与 MAC 可加 --redact 打码）。
"""
from __future__ import annotations
import argparse, hashlib, struct, sys

LINK_ETHERNET = 1
LINK_RAW = 101
LINK_LINUX_SLL = 113
LINK_RAW_BSD = 12
LINK_NULL = 0


def read_pcap(path: str):
    with open(path, "rb") as f:
        data = f.read()
    magic = data[:4]
    if magic == b"\xd4\xc3\xb2\xa1":
        endian, nano = "<", False
    elif magic == b"\xa1\xb2\xc3\xd4":
        endian, nano = ">", False
    elif magic == b"\x4d\x3c\xb2\xa1":
        endian, nano = "<", True
    elif magic == b"\xa1\xb2\x3c\x4d":
        endian, nano = ">", True
    else:
        sys.exit("不是 pcap（如果你抓的是 pcapng，请在 Wireshark 里另存为 pcap）")
    _, _, _, _, _, snaplen, linktype = struct.unpack(endian + "IHHiIII", data[:24])
    offset = 24
    packets = []
    while offset + 16 <= len(data):
        ts_sec, ts_usec, incl, orig = struct.unpack(endian + "IIII", data[offset:offset + 16])
        offset += 16
        frame = data[offset:offset + incl]
        offset += incl
        ts = ts_sec + (ts_usec / (1e9 if nano else 1e6))
        packets.append((ts, frame, linktype))
    return packets


def udp_payload(linktype: int, frame: bytes):
    if linktype == LINK_ETHERNET:
        if len(frame) < 14:
            return None
        ethertype = struct.unpack("!H", frame[12:14])[0]
        offset = 14
        while ethertype in (0x8100, 0x88A8):          # VLAN
            ethertype = struct.unpack("!H", frame[offset + 2:offset + 4])[0]
            offset += 4
        if ethertype != 0x0800:
            return None
        ip = frame[offset:]
    elif linktype in (LINK_RAW, LINK_RAW_BSD):
        ip = frame
    elif linktype == LINK_LINUX_SLL:
        if len(frame) < 16 or struct.unpack("!H", frame[14:16])[0] != 0x0800:
            return None
        ip = frame[16:]
    elif linktype == LINK_NULL:
        ip = frame[4:]
    else:
        return None
    if len(ip) < 20 or (ip[0] >> 4) != 4 or ip[9] != 17:
        return None
    ihl = (ip[0] & 0xF) * 4
    if len(ip) < ihl + 8:
        return None
    src = ".".join(str(b) for b in ip[12:16])
    dst = ".".join(str(b) for b in ip[16:20])
    sport, dport, length = struct.unpack("!HHH", ip[ihl:ihl + 6])
    payload = ip[ihl + 8:ihl + length]
    return src, sport, dst, dport, payload


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("pcap")
    ap.add_argument("--password", required=True)
    ap.add_argument("--port", type=int, default=61440)
    ap.add_argument("--redact", action="store_true")
    args = ap.parse_args()

    packets = read_pcap(args.pcap)
    events = []
    for ts, frame, linktype in packets:
        parsed = udp_payload(linktype, frame)
        if not parsed:
            continue
        src, sport, dst, dport, payload = parsed
        if args.port not in (sport, dport):
            continue
        events.append((ts, src, sport, dst, dport, payload))
    events.sort(key=lambda e: e[0])
    print(f"抓到 {len(events)} 个 61440 端口报文\n")

    def show(text: str) -> str:
        if not args.redact:
            return text
        return text[:3] + "***"

    password = args.password.encode()
    pending_challenge = None
    index = 0
    for ts, src, sport, dst, dport, payload in events:
        if len(payload) == 76 and payload[0] == 0x03:
            salt = payload[0x04:0x08]
            serial = struct.unpack("!H", payload[0x02:0x04])[0]
            pending_challenge = (salt, serial, ts)
            print(f"[{ts:.3f}] 挑战应答 serial=0x{serial:04x} salt={salt.hex()}")
        elif len(payload) == 342 and payload[0] == 0x03:
            index += 1
            digest = payload[0x04:0x14]
            account = payload[0x14:0x14 + 32].split(b"\x00")[0].decode(errors="replace")
            mac = payload[0x14C:0x152].hex(":")
            if pending_challenge:
                salt, serial, _ = pending_challenge
                expected = hashlib.md5(bytes([3, 1]) + salt + password).digest()
                ok = expected == digest
                print(f"[{ts:.3f}] 登录包 #{index} 账号={show(account)} MAC={show(mac)} "
                      f"salt={salt.hex()} 摘要={'✅ 匹配' if ok else '❌ 不匹配'}")
                if not ok:
                    print(f"        包内摘要={digest.hex()}")
                    print(f"        复算摘要={expected.hex()}")
                pending_challenge = None
            else:
                print(f"[{ts:.3f}] 登录包 #{index} 账号={show(account)} —— 前面没有挑战应答，无法复算")
        elif len(payload) == 37 and payload[0] == 0x05:
            reason = payload[0x14:].split(b"\x00")[0].decode(errors="replace")
            print(f"[{ts:.3f}] 服务器拒绝：{reason!r}")
        elif len(payload) == 45:
            print(f"[{ts:.3f}] 登录成功应答")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
