.PHONY: test core-test self-test portal-self-test build release release-probe dump-login app ci clean

# 本工作区跑在受限沙箱里，需要把 SwiftPM 缓存/临时目录指到仓库内。
# 在普通 Mac 上这些变量是可选的（不会造成副作用）。
SANDBOX_ENV = TMPDIR=$(CURDIR)/.build/tmp CLANG_MODULE_CACHE_PATH=$(CURDIR)/.build/modulecache
SWIFT_FLAGS = --disable-sandbox --scratch-path .build --cache-path .build/cache

test:
	$(SANDBOX_ENV) swift test $(SWIFT_FLAGS)

core-test:
	$(SANDBOX_ENV) swift test $(SWIFT_FLAGS) --filter JLUGateCoreTests

# 施工机唯一能做的"联网"动作：对 127.0.0.1 的模拟网关跑完整流程
self-test:
	$(SANDBOX_ENV) swift run $(SWIFT_FLAGS) jlugate-probe --self-test --seconds 8 --keepalive 1

# 网页认证链路：对 127.0.0.1 的模拟门户跑 302 → 登录页 → POST → 204
portal-self-test:
	$(SANDBOX_ENV) swift run $(SWIFT_FLAGS) jlugate-probe --portal-self-test --seconds 6

build:
	$(SANDBOX_ENV) swift build $(SWIFT_FLAGS)

# 打包 universal CLI（CHECKLIST §10.3）
release-probe:
	$(SANDBOX_ENV) swift build -c release --arch arm64 --arch x86_64 $(SWIFT_FLAGS)
	lipo -info .build/apple/Products/Release/jlugate-probe

# 离线核对 342 字节登录包
dump-login:
	$(SANDBOX_ENV) swift run $(SWIFT_FLAGS) jlugate-probe --dump-login \
		--account 20230001 --password test-pass-2024 --salt 49cb720f \
		--hostname test-mac.local --mac 02:00:00:00:00:01

# App 工程由 XcodeGen 生成（需要 brew install xcodegen；正式签名/公证走这条路）
app:
	cd App && xcodegen generate && open JLUGate.xcodeproj

# 没有开发者账号时的本机构建：SwiftPM 产物 + ad-hoc 签名 → dist/JLU Gate.app
app-bundle:
	./scripts/make-app-bundle.sh

# 构建并直接运行（调试用）
run-app: app-bundle
	open "dist/JLU Gate.app"

# 端到端：真实 App + 本地模拟门户（脚本化浏览器，无人值守）
portal-e2e:
	./scripts/portal-app-e2e.sh

# 同上，但弹真实 WKWebView 登录窗（需要手点）
portal-e2e-window:
	./scripts/portal-app-e2e.sh --window

# 本地跑一遍 CI 里的三件事
ci: test self-test portal-self-test
	./scripts/privacy-scan.sh

clean:
	rm -rf .build
