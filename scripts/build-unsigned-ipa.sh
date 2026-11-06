#!/bin/bash
# 一键打未签名 iOS IPA。
#
# 版本规则（与 VERSIONING.md 一致）：
#   默认     只把 CURRENT_PROJECT_VERSION（构建号）+1。对外版本号不动。
#   --patch  修复：对外版本 +0.0.1（1.6 → 1.6.1，1.6.1 → 1.6.2），构建号 +1。
#   --minor  功能：对外版本 +0.1 并去掉补丁位（1.6.1 → 1.7），构建号 +1。
#
# iOS 与 macOS 两个 target 的版本号会一起改，避免分叉。
# 构建失败时会把 project.yml 和 VERSIONING.md 恢复成运行前的内容。
#
# 产物：ci-builds/Beans-<版本>-<构建号>-unsigned.ipa

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="build"
case "${1:-}" in
    "" ) MODE="build" ;;
    --patch ) MODE="patch" ;;
    --minor ) MODE="minor" ;;
    -h|--help )
        sed -n '2,12p' "$0"
        exit 0
        ;;
    * )
        echo "未知参数：$1" >&2
        echo "用法：$0 [--patch|--minor]" >&2
        exit 2
        ;;
esac

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "缺少 xcodegen。先执行：brew install xcodegen" >&2
    exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "缺少 xcodebuild。" >&2
    exit 1
fi

SNAPSHOT="$(mktemp -d)"
cp project.yml "$SNAPSHOT/project.yml"
if [[ -f VERSIONING.md ]]; then
    cp VERSIONING.md "$SNAPSHOT/VERSIONING.md"
fi
restore_version_files() {
    cp "$SNAPSHOT/project.yml" project.yml
    if [[ -f "$SNAPSHOT/VERSIONING.md" ]]; then
        cp "$SNAPSHOT/VERSIONING.md" VERSIONING.md
    fi
    rm -rf "$SNAPSHOT"
}
trap restore_version_files ERR

python3 - "$MODE" <<'PY'
import re
import sys

mode = sys.argv[1]
path = "project.yml"
text = open(path, encoding="utf-8").read()

marketing = re.findall(r'MARKETING_VERSION:\s*"([^"]+)"', text)
builds = re.findall(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', text)
if len(marketing) < 2 or len(set(marketing)) != 1:
    sys.exit("project.yml 里的 MARKETING_VERSION 不一致或不完整：%s" % marketing)
if len(builds) < 2 or len(set(builds)) != 1:
    sys.exit("project.yml 里的 CURRENT_PROJECT_VERSION 不一致或不完整：%s" % builds)

current = marketing[0]
parts = current.split(".")
if not all(part.isdigit() for part in parts) or len(parts) not in (2, 3):
    sys.exit("无法解析版本号：%s" % current)
major, minor = int(parts[0]), int(parts[1])
patch = int(parts[2]) if len(parts) == 3 else None

if mode == "patch":
    version = "%d.%d.%d" % (major, minor, 1 if patch is None else patch + 1)
elif mode == "minor":
    version = "%d.%d" % (major, minor + 1)
else:
    version = current
build = int(builds[0]) + 1

text2, n_ver = re.subn(
    r'(MARKETING_VERSION:\s*")[^"]+(")',
    lambda m: m.group(1) + version + m.group(2),
    text,
)
text2, n_build = re.subn(
    r'(CURRENT_PROJECT_VERSION:\s*")\d+(")',
    lambda m: m.group(1) + str(build) + m.group(2),
    text2,
)
if n_ver != len(marketing) or n_build != len(builds):
    sys.exit("版本号替换数量异常")
open(path, "w", encoding="utf-8").write(text2)

notes = "VERSIONING.md"
try:
    versioning = open(notes, encoding="utf-8").read()
except FileNotFoundError:
    versioning = ""
if versioning:
    updated, n = re.subn(r'(当前版本：)\d+(?:\.\d+)*', r"\g<1>" + version, versioning, count=1)
    if n != 1:
        sys.exit("VERSIONING.md 里找不到「当前版本：」")
    open(notes, "w", encoding="utf-8").write(updated)

open("version.txt", "w", encoding="utf-8").write(version + "\n")
open("build.txt", "w", encoding="utf-8").write(str(build) + "\n")
print("版本 %s（构建号 %s）" % (version, build))
PY

VER="$(cat version.txt)"
BUILD="$(cat build.txt)"
rm -f version.txt build.txt

if ! grep -q "^## ${VER}$" CHANGELOG.md; then
    echo "警告：CHANGELOG.md 没有「## ${VER}」条目。IPA 仍会继续打，发布说明需要补上。" >&2
fi

echo "生成 Xcode 工程…"
xcodegen generate

DERIVED="build/UnsignedIPA"
APP="$DERIVED/Build/Products/Release-iphoneos/Beans.app"

echo "编译未签名 Release…"
xcodebuild \
    -project Beans.xcodeproj \
    -scheme Beans \
    -configuration Release \
    -sdk iphoneos \
    -derivedDataPath "$DERIVED" \
    MARKETING_VERSION="$VER" \
    CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build

SHORT="$(plutil -extract CFBundleShortVersionString raw "$APP/Info.plist")"
BUNDLE_BUILD="$(plutil -extract CFBundleVersion raw "$APP/Info.plist")"
if [[ "$SHORT" != "$VER" || "$BUNDLE_BUILD" != "$BUILD" ]]; then
    echo "版本校验失败：包内 ${SHORT} (${BUNDLE_BUILD})，期望 ${VER} (${BUILD})" >&2
    exit 1
fi

if codesign -dv "$APP" >/dev/null 2>&1; then
    echo "签名校验失败：Beans.app 带有签名" >&2
    exit 1
fi

OUT_DIR="ci-builds"
OUT="$OUT_DIR/Beans-${VER}-${BUILD}-unsigned.ipa"
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload" "$OUT_DIR"
cp -R "$APP" "$STAGE/Payload/"
rm -f "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$STAGE/Payload" "$OUT"
rm -rf "$STAGE"

# 不用 grep -q：它提前退出会让 unzip 收到 SIGPIPE，在 pipefail 下被误判为失败。
listing="$(unzip -l "$OUT")"
if [[ "$listing" != *"Payload/Beans.app/Info.plist"* ]]; then
    echo "IPA 结构不对，缺少 Payload/Beans.app" >&2
    exit 1
fi

trap - ERR
rm -rf "$SNAPSHOT"

echo "未签名 IPA：$ROOT/$OUT"
ls -lh "$OUT"
echo "CFBundleShortVersionString=$SHORT CFBundleVersion=$BUNDLE_BUILD 未签名"
