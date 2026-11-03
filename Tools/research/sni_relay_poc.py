#!/usr/bin/env python3
"""PoC: 透明转发器。
从 TLS ClientHello 里取 SNI（不依赖 /dev/pf、不依赖代理软件），
然后要么直连目标，要么经上游 HTTP 代理 CONNECT 出去。
"""
import argparse, socket, struct, sys, threading

def recv_client_hello(sock):
    buf = b""
    while len(buf) < 5:
        d = sock.recv(4096)
        if not d: return None, buf
        buf += d
    if buf[0] != 0x16:            # 不是 TLS handshake
        return None, buf
    need = 5 + struct.unpack(">H", buf[3:5])[0]
    while len(buf) < need:
        d = sock.recv(4096)
        if not d: break
        buf += d
    return buf[:need], buf

def parse_sni(rec):
    try:
        p = 5                                   # record header
        assert rec[p] == 0x01                   # ClientHello
        p += 4                                  # type + 3 字节长度
        p += 2 + 32                             # version + random
        p += 1 + rec[p]                         # session id
        p += 2 + struct.unpack(">H", rec[p:p+2])[0]     # cipher suites
        p += 1 + rec[p]                         # compression
        if p + 2 > len(rec): return None
        end = p + 2 + struct.unpack(">H", rec[p:p+2])[0]
        p += 2
        while p + 4 <= end:
            etype, elen = struct.unpack(">HH", rec[p:p+4]); p += 4
            if etype == 0x0000:                 # server_name
                q = p + 2                       # list length
                while q + 3 <= p + elen:
                    ntype = rec[q]; nlen = struct.unpack(">H", rec[q+1:q+3])[0]
                    if ntype == 0:
                        return rec[q+3:q+3+nlen].decode()
                    q += 3 + nlen
            p += elen
    except Exception:
        pass
    return None

def pipe(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d: break
            b.sendall(d)
    except Exception:
        pass
    finally:
        for s in (a, b):
            try: s.shutdown(socket.SHUT_RDWR)
            except Exception: pass

def handle(conn, upstream, port):
    hello, remainder = recv_client_hello(conn)
    if hello is None:
        conn.close(); return
    sni = parse_sni(hello) or ""
    target = sni or "?"
    print(f"[relay] SNI={sni!r} 首包={len(remainder)}B", flush=True)
    try:
        if upstream:
            host, up_port = upstream
            up = socket.create_connection((host, up_port), timeout=8)
            up.sendall(f"CONNECT {sni}:{port} HTTP/1.1\r\nHost: {sni}:{port}\r\n\r\n".encode())
            resp = up.recv(4096)
            if b" 200 " not in resp.split(b"\r\n")[0]:
                print(f"[relay] 上游拒绝: {resp[:60]!r}", flush=True)
                conn.close(); up.close(); return
        else:
            up = socket.create_connection((sni, port), timeout=8)
        up.sendall(remainder)
        threading.Thread(target=pipe, args=(conn, up), daemon=True).start()
        pipe(up, conn)
    except Exception as e:
        print(f"[relay] 失败 {sni}: {e}", flush=True)
        try: conn.close()
        except Exception: pass

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--listen", default="127.0.0.1:8443")
    ap.add_argument("--upstream", default=None, help="host:port，HTTP 代理；不填则直连")
    ap.add_argument("--port", type=int, default=443, help="CONNECT 的目标端口")
    a = ap.parse_args()
    h, p = a.listen.rsplit(":", 1)
    up = tuple(a.upstream.rsplit(":", 1)) if a.upstream else None
    if up: up = (up[0], int(up[1]))
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((h, int(p))); srv.listen(16)
    print(f"[relay] listening {a.listen} upstream={up or 'direct'}", flush=True)
    while True:
        c, _ = srv.accept()
        threading.Thread(target=handle, args=(c, up, a.port), daemon=True).start()

if __name__ == "__main__":
    main()
