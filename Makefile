# TuneC — 常用开发任务
#
# 用法: make [目标]      （直接执行 make 或 make help 打印全部目标）

SHELL := /bin/bash

# 签名身份：默认为 "-"（ad-hoc 签名）。传入证书名可启用持久化签名：
#   make build SIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
SIGN_IDENTITY ?= -
export SIGN_IDENTITY

APP := build/TuneC.app
BIN := $(APP)/Contents/MacOS/TuneC

.PHONY: help build debug universal selfcheck run clean verify
.DEFAULT_GOAL := help

help:
	@echo "TuneC 可用目标:"
	@echo "  make build      构建 release 版（会部署到 ~/Applications，见下方说明）"
	@echo "  make debug      构建 debug 版（同样会部署到 ~/Applications）"
	@echo "  make universal  构建 arm64 + x86_64 通用版（发版用，会部署）"
	@echo "  make selfcheck  对已构建产物运行 --selfcheck"
	@echo "  make run        启动已构建的 App"
	@echo "  make verify     构建通用版 + 自检，不部署（等价于 CI 的校验步骤）"
	@echo "  make clean      删除 build/ 与 .build/，并清理伴生文件"
	@echo ""
	@echo "变量: SIGN_IDENTITY（默认 '-'，即 ad-hoc 签名）"
	@echo ""
	@echo "注意: build / debug / universal 会按 scripts/build.sh 的默认行为部署到"
	@echo "      ~/Applications/TuneC.app（本机开发者意图）；只想构建请用 NODEPLOY=1，"
	@echo "      或直接用 make verify。"

# 构建并部署到 ~/Applications（本机开发者的默认意图）
build:
	bash scripts/build.sh release

debug:
	bash scripts/build.sh debug

universal:
	UNIVERSAL=1 bash scripts/build.sh release

selfcheck:
	@test -x "$(BIN)" || { echo "❌ 未找到构建产物: $(BIN)（请先运行 make build）"; exit 1; }
	@"$(BIN)" --selfcheck

run:
	@test -d "$(APP)" || { echo "❌ 未找到 $(APP)（请先运行 make build）"; exit 1; }
	open "$(APP)"

# 与 CI 一致：通用二进制 + 不部署。
# CI 的校验步骤是 UNIVERSAL=1 NODEPLOY=1 bash scripts/build.sh release（见
# .github/workflows/ci.yml），这里保持完全相同，避免覆盖用户的 ~/Applications/TuneC.app。
verify:
	UNIVERSAL=1 NODEPLOY=1 bash scripts/build.sh release
	$(MAKE) selfcheck

clean:
	@rm -rf build .build
	@find . -name '._*' -delete 2>/dev/null || true
	@find . -name '.DS_Store' -delete 2>/dev/null || true
	@echo "🧹 已清理 build/ 与 .build/"
