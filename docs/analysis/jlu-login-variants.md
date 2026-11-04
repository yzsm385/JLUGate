# JLU Dr.Com 登录报文：各成功实现的对比与结论

> 背景：我们的客户端一直收到 `ldap auth error`。查清后发现**服务端返回的第 4 字节是错误码**，
> 我们之前只看了字符串，把"版本不兼容"误当成"密码错"。

## 关键发现：错误码 0x15 = 版本不兼容

我们抓到的拒绝帧：`05 00 00 05 15 00 … "ldap auth error"`。
第 4 字节 `0x15` 在两套独立实现里有同一含义：

| 实现 | 0x15 的含义 |
|---|---|
| [jlu-drcom-ng v2.0.0](https://github.com/hZsFN/jlu-drcom-ng) | `CLIENT_UPGRADE_REQUIRED` — 需要升级客户端 |
| [sidravia](https://github.com/CaelestisAstesia/sidravia)（Go） | `incompatible_version` — 协议版本与服务端不兼容 |

也就是说：**登录失败与密码无关**，是我们的报文版本标识太旧。

## 各实现用的报文版本

| 实现 | 基础长度 | 密码段起点 | 0x6E 处 | 0xB6 魔数后 | 0xF6 服务包 | 备注 |
|---|---|---|---|---|---|---|
| [jlu-drcom-ng](https://github.com/hZsFN/jlu-drcom-ng) v2.0.0 | 338 | 312 | `LIYUANYUAN` | `…CF 07 68` | `3dc79f52…` | **当前维护、含测试**；本文采用 |
| 本仓库 2026-11-02 抓包 | 334+(p-1)/4*4 | 312 | 主机名 | `…CF 07 6A` | `56c68373…` | 旧版官方客户端 |
| [JKDrcom](https://github.com/Winterreisender/JKDrcom) | 334+(p-1)/4*4 | 312 | 主机名 | `…CF 07 6A` | `1c210c99…` | Kotlin，2019 |
| [AndrewLawrence80](https://github.com/AndrewLawrence80/jlu-drcom-client) / [yeqf911](https://github.com/yeqf911/jlu-drcom-client) | 338 | 312 | 主机名 | — | — | C/Python 早期版本 |
| [JonathanKang](https://github.com/JonathanKang/jlu-drcom-client) | 338 | — | `0x69×8` | — | — | Android 版，另有变体 |

结论：**固定常量（版本串、服务包、尾部标记）是"客户端版本"，服务端按它能接受的版本校验。**
我们照 11-02 的抓包写死旧常量，服务端就回 0x15。

## 我们的处理

1. **默认使用 jlu-drcom-ng v2.0.0 的布局**（`LoginVariant.current`）；
2. 若服务端回 `0x15`，**自动切换到 11-02 抓包的旧版布局**再试一次（`LoginVariant.legacy`）；
3. 仍失败才报错，并把错误码翻译成人话（例如"需要升级客户端版本：不是密码问题"）。

两套布局都有**逐字节黄金测试**：

- `Fixtures/login_jlu_v2_golden.json`：由 jlu-drcom-ng 的 `build_login_packet` 生成（3 种密码长度）
- `Fixtures/login_jlu_legacy_golden.json`：由"能复现 11-02 真实抓包"的参考实现生成
- 另外用真实抓包核对过：旧版布局能 100% 复现 `local/PRIVATE.md` 里那帧 342 字节登录包

## 各字段算法（两版相同）

```
md5a  = MD5(03 01 ‖ salt ‖ password)
md5b  = MD5(01 ‖ password ‖ salt ‖ 00 00 00 00)
md5c  = MD5(前 97 字节 ‖ 14 00 07 0B)[0..8]
xor   = md5a[0..6] XOR mac
ror[i]= ((md5a[i] XOR password[i]) << 3) + (>> 5)
sum   = XOR-fold(小端 u32, 初值 1234) × 1968，小端写出
```

差别只在：长度、固定常量、尾部标记、以及 `sum` 的输入范围。
