# 抓包目录（不入库）

本目录用于**本地**临时存放 `.pcap`，已被 `.gitignore` 排除，不会进入仓库。

- 需要复现协议时，把 `tcpdump -i <if> -w login.pcap "udp port 61440"` 的产物放这里；
- 解析完请**删除**，或改造成脱敏夹具（见 `Fixtures/README.md`）后再提交；
- 提交前务必跑一遍 `./scripts/privacy-scan.sh`。

> 历史上这里曾放过一份真实抓包，开源前已删除；`.gitignore` 现在永久排除 `*.pcap` / `*.pcapng` / `*.har`。
