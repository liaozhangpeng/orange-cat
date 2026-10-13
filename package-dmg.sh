#!/bin/zsh
# Builds the app and packages it as build/OrangeCat.dmg for sharing.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

STAGE=build/dmg
DMG=build/OrangeCat.dmg
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/OrangeCat.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/首次打开说明.txt" <<'TXT'
安装：把「OrangeCat」拖进「Applications」文件夹。

首次打开：这个 App 没有经过 Apple 公证，第一次打开时系统会提示无法验证开发者。
  1. 在「应用程序」里双击 OrangeCat，看到提示后点「完成」/「好」
  2. 打开「系统设置」→「隐私与安全性」，拉到底部，点「仍要打开」
  3. 再次打开 OrangeCat，点「打开」
之后就能正常使用了。

如果提示「已损坏，无法打开」，在「终端」里执行下面这行再打开：
  xattr -dr com.apple.quarantine /Applications/OrangeCat.app

玩法：点猫和它互动，它会丢出毛线球；点毛线球把球丢回给它，它会接着玩。
可以拖动猫换位置。菜单栏的 🐱 可以控制它或退出。
TXT

hdiutil create -volname "OrangeCat 橘猫" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "Built $DMG ($(du -h "$DMG" | cut -f1))"
