#!/usr/bin/env python3
"""模拟校园网页认证（captive portal），供 JLU Gate 离线自测。

行为（与 PLAN §5.4 的判定流程一一对应）：

    GET  /generate_204   → 未登录：302 到 /portal ；已登录：204 No Content
    GET  /portal         → 200 登录页（<form action="/login">，标准 input）
    POST /login          → 账号密码对：Set-Cookie + 302 /ok ；错：200 + 错误文案
    GET  /drcom/login    → Dr.COM 4.0 网页登录接口（吉大实际用的就是它）
                           JSONP，result=1 成功 / result=0 + msg + msga 失败
    GET  /ok             → 200 "login ok"
    POST /logout         → 清会话

用法：

    python3 Tools/mock-portal/portal_server.py --port 18080 --user 20230001 --password test-pass-2024

这里**故意**把 /generate_204 做成"跟随跳转后是 200 页面"的真实门户形态，
因为真实校园网就是这样：不是 204，而是把你带到登录页。
"""

from __future__ import annotations

import argparse
import http.server
import socketserver
import urllib.parse

LOGIN_PAGE = """<!doctype html>
<html><head><meta charset="utf-8"><title>校园网认证</title></head>
<body>
  <h1>请登录校园网</h1>
  <form method="post" action="/login">
    <input type="text" name="username" placeholder="学号">
    <input type="password" name="password" placeholder="密码">
    <button type="submit">登录</button>
  </form>
</body></html>
"""

STATE = {"logged_in": False}


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "JLUMockPortal/1.0"
    user = "20230001"
    password = "test-pass-2024"

    # ---------- 工具 ----------

    def _send(self, status: int, body: str = "", headers: dict | None = None) -> None:
        payload = body.encode()
        self.send_response(status)
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)

    def log_message(self, fmt: str, *args) -> None:  # noqa: A003
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}", flush=True)

    # ---------- 路由 ----------

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        query = urllib.parse.parse_qs(parsed.query)

        # Dr.COM 4.0 网页登录接口（吉大 net.jlu.edu.cn 实际走的就是这个）：
        # GET /drcom/login?callback=dr1003&DDDDD=...&upass=...&0MKKey=123456
        # 成功 → JSONP result=1；失败 → result=0 + msg/msga。
        if path == "/drcom/login":
            user = query.get("DDDDD", [""])[0].split("@", 1)[0]
            password = query.get("upass", [""])[0]
            if user == self.user and password == self.password:
                STATE["logged_in"] = True
                payload = (f'{query.get("callback", ["dr1003"])[0]}'
                           f'({{"result":1,"msg":1,"uid":"{user}","ss4":"020000000001"}})')
            else:
                payload = (f'{query.get("callback", ["dr1003"])[0]}'
                           f'({{"result":0,"msg":1,"msga":"userid error1",'
                           f'"uid":"{user}","ss4":"020000000001"}})')
            body = payload.encode("gbk")
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=gbk")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        # 仅测试夹具：`?autologin=1` 直接置为已登录，方便自动化验证
        # （App 侧不做任何 DOM 操作——决策 D-001）
        if path == "/portal" and query.get("autologin", ["0"])[0] == "1":
            STATE["logged_in"] = True
            self._send(302, "", {"Location": "/ok"})
            return
        if path == "/generate_204":
            if STATE["logged_in"]:
                self.send_response(204)
                self.send_header("Content-Length", "0")
                self.end_headers()
            else:
                self._send(302, "", {"Location": f"http://{self.headers.get('Host')}/portal"})
            return
        if path == "/portal":
            self._send(200, LOGIN_PAGE)
            return
        if path == "/ok":
            self._send(200, "login ok")
            return
        self._send(404, "not found")

    def do_POST(self) -> None:  # noqa: N802
        path = urllib.parse.urlparse(self.path).path
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode(errors="replace")
        fields = urllib.parse.parse_qs(body)

        if path == "/login":
            user = fields.get("username", [""])[0]
            password = fields.get("password", [""])[0]
            if user == self.user and password == self.password:
                STATE["logged_in"] = True
                self._send(302, "", {
                    "Location": "/ok",
                    "Set-Cookie": "jlu_session=ok; Path=/; HttpOnly",
                })
            else:
                self._send(200, "用户名或密码错误")
            return

        if path == "/logout":
            STATE["logged_in"] = False
            self._send(200, "logged out")
            return

        self._send(404, "not found")


def main() -> int:
    parser = argparse.ArgumentParser(description="模拟校园网页认证")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18080)
    parser.add_argument("--user", default="20230001")
    parser.add_argument("--password", default="test-pass-2024")
    args = parser.parse_args()

    Handler.user = args.user
    Handler.password = args.password

    class Server(socketserver.TCPServer):
        allow_reuse_address = True

    with Server((args.host, args.port), Handler) as server:
        print(f"mock portal listening on http://{args.host}:{args.port}", flush=True)
        print(f"  /generate_204  302(未登录)/204(已登录)", flush=True)
        print(f"  /portal        登录页", flush=True)
        print(f"  账号密码       {args.user} / {args.password}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
