import socket, threading, select, sys
def pipe(a,b):
    try:
        while True:
            d=a.recv(65536)
            if not d: break
            b.sendall(d)
    except Exception: pass
    finally:
        for s in (a,b):
            try: s.shutdown(socket.SHUT_RDWR)
            except Exception: pass
def handle(c):
    data=b""
    while b"\r\n\r\n" not in data:
        d=c.recv(4096)
        if not d: return
        data+=d
    line=data.split(b"\r\n")[0].decode()
    if not line.startswith("CONNECT"):
        c.close(); return
    host,port=line.split()[1].rsplit(":",1)
    print(f"[proxy] CONNECT {host}:{port}",flush=True)
    up=socket.create_connection((host,int(port)),timeout=8)
    c.sendall(b"HTTP/1.1 200 Connection Established\r\n\r\n")
    threading.Thread(target=pipe,args=(c,up),daemon=True).start()
    pipe(up,c)
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(("127.0.0.1",7890)); s.listen(8)
print("[proxy] listening 127.0.0.1:7890",flush=True)
while True:
    c,_=s.accept(); threading.Thread(target=handle,args=(c,),daemon=True).start()
