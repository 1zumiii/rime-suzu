Suzu 一键安装（macOS）

适用：Apple 芯片（M1 及以后）的 Mac，macOS 13 或更新，鼠须管（Squirrel）。

步骤
1. 先装好鼠须管：https://github.com/rime/squirrel/releases （已装过可跳过；装了 Homebrew 的话，脚本会问是否替你装）。
2. 解压本压缩包，双击 install.command。
   如果提示“无法验证开发者”，右键 install.command，选“打开”；或在终端里进入解压出来的文件夹，运行 bash install.command。
3. 等脚本跑完（首次编译词库约 1 到 2 分钟）。
4. 系统设置 -> 键盘 -> 输入法 -> 编辑 -> 加号 -> 中文 -> 鼠须管，添加后用 Control+空格 切换。

用法
- 打字试试：zm、jingli。候选后面带 ◇ 表示 Suzu 参与了排序。
- Control+Shift+5 临时开关 AI。
- 可选：bash install.command --with-gram 另外下载万象语法模型（约 380 MB），整句候选更好，不装也能用。

隐私
- 模型和推理都在你的 Mac 上，输入内容不会上传。
- 选词统计、语料记录、输入事件流这类开发用的功能全部关闭，脚本不会创建它们的开关。

还原与卸载
- 安装前的配置备份在“~/Library/Rime.backup-时间”，改回 ~/Library/Rime 的名字即可还原。
- 只关闭 AI：删除 ~/Library/Rime/lua/rime_llm.so，重新部署。

遇到问题：https://github.com/1zumiii/rime-suzu/issues
