# 发布到 GitHub

> 目标：把仓库推上去，同时保证 `local/`（真实凭据与原始样本）**永远不进远程**。

---

## 0. 推送前自检（每次都要）

```bash
./scripts/privacy-scan.sh          # 必须输出 ✅
make test                          # 必须 52 条全绿
git status --ignored --short | grep local   # 应能看到 !! local/
```

三项都对，再往下走。

---

## 1. 第一次提交

仓库目前是 **0 个提交**，正好从干净状态开始：

```bash
cd ~/Documents/JLUGate

git add -A
git status --short | head          # 确认没有任何 local/ 或 *.pcap
git commit -m "JLUGate 0.1.0: 协议编解码、通道、状态机、UI（夹具已脱敏）"
```

> 提交会触发 `.git/hooks/pre-commit`：若误加了 `local/` 或含真实 MAC/学号/IP 的文件，会**直接拒绝**。

---

## 2. 建远程并绑定

在 GitHub 上新建仓库时选 **空仓库**（不要勾 README / .gitignore / license，否则首推会冲突）。

```bash
git branch -M main
git remote add origin git@github.com:<你的用户名>/JLUGate.git
```

用 HTTPS 的话把地址换成：

```bash
git remote add origin https://github.com/<你的用户名>/JLUGate.git
```

检查：

```bash
git remote -v
```

---

## 3. 推送

```bash
git push -u origin main
```

如果是第一次用 SSH，先确认密钥已加：

```bash
ssh -T git@github.com     # 出现 "Hi <用户名>!" 即可
```

---

## 4. 推送后必须做的三项验证

```bash
# ① 远程没有私密目录
git ls-tree -r --name-only origin/main | grep -Ei 'local/|\.pcap|PRIVATE' && echo "⚠️ 有泄漏！" || echo "✅ 干净"

# ② 确认被忽略
git check-ignore -v local/PRIVATE.md

# ③ 网页上抽查
open https://github.com/<你的用户名>/JLUGate
```

在 GitHub 网页里搜一下你的学号、密码前几位、网卡 MAC 前几位，结果都应为 0。

---

## 5. 万一误推了

```bash
# 立刻从远程移除（保留本地文件）
git rm -r --cached local
git commit -m "chore: 移除误提交的本地私密文件"
git push
```

但**历史里仍留有内容**，必须改写历史：

```bash
brew install git-filter-repo
git filter-repo --path local --invert-paths
git push --force
```

然后：**立刻改掉那个账号的密码**，并联系学校网络中心确认没有异常登录。
（密码一旦进过远程，就当作已泄露。）

---

## 6. 私密文件怎么放

现在在 `local/PRIVATE.md`，已被 `.gitignore` 与钩子双重拦截。两个更强的选择：

```bash
# 方案 A：移出仓库
mv local ~/Documents/JLUGate-private

# 方案 B：加密磁盘映像，平时不挂载
hdiutil create -encryption AES-256 -srcformat UDZO -srcfolder local ~/Documents/JLUGate-private.dmg
```

---

## 7. 之后每次提交

```bash
git add -A
git commit -m "…"        # 钩子自动跑隐私检查
git push
```
