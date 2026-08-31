# 自定义 Touch Bar 角色

Touch Bar 助手默认显示项目内置的雷姆图片。你可以用自己的动漫角色 PNG 覆盖它，不需要修改 Codex.app，也不会影响 Hermes。

## 快速更换

在项目根目录运行：

```bash
./scripts/set-character.sh "/绝对路径/你的角色.png"
```

角色会被复制到：

```text
~/.config/codex-touchbar/character.png
```

助手会自动请求刷新；如果 Touch Bar 当前没有立即变化，切换一次应用再回到 Codex 即可。

恢复内置雷姆：

```bash
./scripts/set-character.sh --reset
```

## 图片建议

- 使用透明背景 PNG，建议正方形画布，尺寸约 64–256 像素。
- 角色主体尽量居中并裁掉多余空白，否则 Touch Bar 中会显得很小。
- 文件建议小于 1 MB；全身立绘可以改用半身或头像裁剪版。
- 图片仅保存在本机的 `~/.config/codex-touchbar/`，不会自动上传到 GitHub。

Touch Bar 中角色区域会按比例缩放到约 20×30 点；额度条和角色图片是分开的，替换图片不会改变额度读取逻辑。

## 从 GitHub 重新安装

克隆项目后先安装独立助手：

```bash
./scripts/install-codex-touchbar-helper.sh
./scripts/set-character.sh "/绝对路径/你的角色.png"
```

仓库内的默认 `Sources/CodexUsageWidget/Resources/rem.png` 仍然作为备用图片，因此没有自定义图片时开箱即用。
