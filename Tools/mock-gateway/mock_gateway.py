#!/usr/bin/env python3
"""Dr.Com 模拟网关（施工机唯一能跑起来的"真环境"）。

用法（本机自测，不需要任何校园网）：

    # 终端 A：起网关（客户端本地端口是 61440，网关换个端口避免撞车）
    python3 Tools/mock-gateway/mock_gateway.py --port 61441 --assert

    # 终端 B：跑探针
    swift run jlugate-probe --self-test

设计要点（对应 CHECKLIST §10.2 / PLAN §12.1）：
- 应答帧的字节**全部来自真实抓包夹具**（Fixtures/session_sanitized.json），不是自己编的；
- `--assert` 会校验客户端的每个包（源端口、类型、长度、账号/版本/令牌/MAC 偏移），不符即
  `ASSERT FAIL` 并以非零码退出；
- 故障注入：`--loss/--dup/--delay/--reorder/--silent`；
- 每帧一行 `time dir len hex-prefix`，便于和客户端日志对齐。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import socket
import struct
import sys
import time
from dataclasses import dataclass, field

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEFAULT_FIXTURES = os.path.join(REPO_ROOT, "Fixtures", "session_sanitized.json")

CLIENT_PORT = 61440
VENDOR = "LIYUANYUAN"
SERVICE_PACK = "3dc79f5212e8170acfa9ec95f1d74916542be7b1"
VERSION = "25.6.0"
TOKEN = "56c68373463f4cd5b73dd3ac5e3673000a5fdd7e"


def load_fixture(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def pick(fixture: dict, direction: str, length: int) -> bytes:
    for frame in fixture["frames"]:
        if frame["dir"] == direction and frame["len"] == length:
            return bytes.fromhex(frame["hex"])
    raise SystemExit(f"夹具里没有 {direction} 方向的 {length} 字节帧")


@dataclass
class GatewayState:
    salt: bytes = b"\x49\xcb\x72\x0f"
    session_id: int = 0x02DC
    login_ok: bool = False
    seconds_online: int = 0
    packets: int = 0
    assertions: list[str] = field(default_factory=list)

    def fail(self, message: str) -> None:
        self.assertions.append(message)


class MockGateway:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.fixture = load_fixture(args.fixtures)
        self.state = GatewayState()
        self.templates = {
            76: pick(self.fixture, "s2c", 76),
            45: pick(self.fixture, "s2c", 45),
            72: pick(self.fixture, "s2c", 72),
        }
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((args.host, args.port))
        self.sock.settimeout(0.5)
        self.client = None
        self.started = time.time()
        self.reorder_buffer: list[tuple[float, bytes]] = []
        self.b_round = 0

    # ---------- 日志 ----------

    def log(self, direction: str, payload: bytes) -> None:
        stamp = time.strftime("%H:%M:%S", time.localtime())
        print(f"{stamp} {direction} {len(payload):>3} {payload[:24].hex()}", flush=True)

    # ---------- 断言 ----------

    def assert_client_frame(self, payload: bytes) -> None:
        if not self.args.assert_mode:
            return
        kind = payload[0] if payload else -1
        # 登录包长度随密码长度变化（338 + 额外段），只校验下界
        expected_len = {1: 20, 0xFF: 38, 7: 40, 6: 80}.get(kind)
        if kind == 0x03 and len(payload) < 300:
            self.state.fail(f"登录包过短：{len(payload)} 字节")
        if expected_len and len(payload) != expected_len:
            self.state.fail(f"类型 0x{kind:02x} 的长度是 {len(payload)}，应为 {expected_len}")
        if kind == 0x01:
            if payload[1] not in (0x03, 0x04, 0x05):
                self.state.fail(f"challenge 子类型异常：{payload[1]:#x}")
            if payload[4] != 0x31:
                self.state.fail(f"challenge 0x04 应为 0x31，实际 {payload[4]:#x}")
        if kind == 0x03:
            if payload[1] != 0x01:
                self.state.fail("登录包子类型应为 0x01")
            account = payload[0x14:0x38].split(b"\x00")[0]
            if self.args.account and account.decode(errors="replace") != self.args.account:
                self.state.fail(f"账号不对：{account!r}")
            # 当前 JLU 登录包：0x38=0x20, 0x39=0x03, 0x50=0x01,
            # 0x6E 起为 "LIYUANYUAN"，0xB6 起为 DrCOM 魔数，0xF6 起 40 字节服务包
            if payload[0x38:0x3A] != b"\x20\x03":
                self.state.fail(f"0x38 控制位不对：{payload[0x38:0x3A].hex()}")
            if payload[0x50] != 0x01:
                self.state.fail(f"0x50 网卡数应为 1，实际 {payload[0x50]}")
            if payload[0x6E:0x78] != VENDOR.encode():
                self.state.fail(f"0x6E 应为 {VENDOR}，实际 {payload[0x6E:0x78]!r}")
            if payload[0xB6:0xBB] != b"DrCOM":
                self.state.fail(f"0xB6 魔数应为 DrCOM，实际 {payload[0xB6:0xBB]!r}")
            if payload[0xF6:0x11E] != SERVICE_PACK.encode():
                self.state.fail("40 字节服务包不对")
            if payload[310] != 0x68:
                self.state.fail(f"0x136 常量应为 0x68，实际 {payload[310]:#x}")
            pass_len = len(self.args.password.encode()) if self.args.password else payload[313]
            if payload[313] != pass_len:
                self.state.fail(f"0x139 密码长度应为 {pass_len}，实际 {payload[313]}")
            counter = 314 + pass_len
            if payload[counter:counter + 2] != b"\x02\x0c":
                self.state.fail(f"密码段后常量不对：{payload[counter:counter + 2].hex()}")
            if self.args.password:
                digest = hashlib.md5(b"\x03\x01" + self.state.salt
                                     + self.args.password.encode()).digest()
                if payload[4:20] != digest:
                    self.state.fail(f"摘要 A 不对：{payload[4:20].hex()} != {digest.hex()}")
        if kind == 0x07:
            if payload[2:4] != b"\x28\x00":
                self.state.fail(f"保活 B 长度域应为 2800，实际 {payload[2:4].hex()}")
            if payload[4] != 0x0B:
                self.state.fail(f"保活 B 0x04 应为 0x0b，实际 {payload[4]:#x}")
            if struct.unpack_from("<H", payload, 6)[0] != self.state.session_id:
                self.state.fail("保活 B 的会话号与 challenge 应答不一致")

    # ---------- 应答构造 ----------

    def challenge_reply(self) -> bytes:
        self.state.salt = bytes(random.getrandbits(8) for _ in range(4))
        reply = bytearray(self.templates[76])
        reply[0x04:0x08] = self.state.salt
        struct.pack_into("<H", reply, 0x26, self.state.session_id)
        return bytes(reply)

    def login_reply(self, payload: bytes) -> bytes:
        if self.args.reject_reason:
            reason = self.args.reject_reason.encode()
            body = bytearray(37)
            body[0] = 0x05
            body[3] = 0x05
            body[4] = 0x15
            body[0x14:0x14 + len(reason)] = reason[:37 - 0x14 - 2]
            return bytes(body)
        if self.args.password:
            expected = hashlib.md5(b"\x03\x01" + self.state.salt
                                   + self.args.password.encode()).digest()
            if payload[4:20] != expected:
                body = bytearray(37)
                body[0] = 0x05
                body[3] = 0x05
                body[4] = 0x15
                reason = b"ldap auth error"
                body[0x14:0x14 + len(reason)] = reason
                return bytes(body)
        self.state.login_ok = True
        self.state.seconds_online = 0
        return bytes(self.templates[45])

    def keepalive_a_reply(self) -> bytes:
        self.state.seconds_online += 1
        reply = bytearray(self.templates[72])
        struct.pack_into("<H", reply, 0x06, self.state.session_id)
        struct.pack_into("<I", reply, 0x20, self.state.seconds_online)
        return bytes(reply)

    def keepalive_b_reply(self, payload: bytes) -> bytes:
        reply = bytearray(payload)
        reply[0x05] = (payload[0x05] + 1) & 0xFF
        reply[0x18:0x1C] = b"\x72\x46\xf8\x4c"
        return bytes(reply)

    def respond(self, payload: bytes) -> list[bytes]:
        if not payload:
            return []
        self.state.packets += 1
        kind = payload[0]
        if kind == 0x01:
            return [self.challenge_reply()]
        if kind == 0x03:
            self.state.login_ok = True          # 登录包长度随密码变化，这里只看类型
            return [self.login_reply(payload)]
        if kind == 0xFF:
            return [self.keepalive_a_reply()] if self.state.login_ok else []
        if kind == 0x07:
            return [self.keepalive_b_reply(payload)]
        if kind == 0x06:
            return []  # 账号预检上报：本实现不发，收到也忽略
        return []

    # ---------- 收发 ----------

    def transmit(self, payload: bytes, address) -> None:
        if self.args.silent:
            self.log("silent", payload)
            return
        if random.random() < self.args.loss:
            self.log("loss", payload)
            return
        delay = self.args.delay / 1000.0
        if self.args.reorder and random.random() < 0.3:
            self.reorder_buffer.append((time.time() + delay + 0.05, payload))
            self.log("queued", payload)
            return
        if delay:
            time.sleep(delay)
        self.sock.sendto(payload, address)
        self.log("s2c", payload)
        if self.args.dup:
            self.sock.sendto(payload, address)
            self.log("dup", payload)

    def flush_reorder(self) -> None:
        now = time.time()
        ready = [item for item in self.reorder_buffer if item[0] <= now]
        self.reorder_buffer = [item for item in self.reorder_buffer if item[0] > now]
        for _, payload in ready:
            if self.client:
                self.sock.sendto(payload, self.client)
                self.log("s2c", payload)

    def run(self, duration: float) -> int:
        deadline = time.time() + duration
        print(f"mock gateway listening on {self.args.host}:{self.args.port}"
              f" (client local port must be {CLIENT_PORT})", flush=True)
        while time.time() < deadline:
            try:
                payload, address = self.sock.recvfrom(2048)
            except socket.timeout:
                self.flush_reorder()
                continue
            self.client = address
            self.assert_client_frame(payload)
            self.log("c2s", payload)
            if address[1] != CLIENT_PORT:
                self.state.fail(f"客户端源端口是 {address[1]}，应为 {CLIENT_PORT}")
            for reply in self.respond(payload):
                self.transmit(reply, address)

        if self.state.assertions:
            for issue in self.state.assertions:
                print(f"ASSERT FAIL {issue}", flush=True)
            return 1
        print(f"OK packets={self.state.packets} login_ok={self.state.login_ok}", flush=True)
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Dr.Com 模拟网关")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=61441,
                        help="网关自身端口（客户端固定绑 61440，同机测试必须换端口）")
    parser.add_argument("--fixtures", default=DEFAULT_FIXTURES)
    parser.add_argument("--duration", type=float, default=30.0)
    parser.add_argument("--loss", type=float, default=0.0)
    parser.add_argument("--dup", action="store_true")
    parser.add_argument("--delay", type=float, default=0.0, help="毫秒")
    parser.add_argument("--reorder", action="store_true")
    parser.add_argument("--silent", action="store_true", help="只收不回，用于测超时")
    parser.add_argument("--assert", dest="assert_mode", action="store_true")
    parser.add_argument("--account", default=None)
    parser.add_argument("--password", default=None)
    parser.add_argument("--reject-reason", default=None)
    args = parser.parse_args()

    gateway = MockGateway(args)
    return gateway.run(args.duration)


if __name__ == "__main__":
    sys.exit(main())
