Suzu 一键安装（Windows）

适用：64 位 Windows，小狼毫（Weasel）0.17。

步骤
1. 先装好小狼毫：https://github.com/rime/weasel/releases （已装过可跳过）。
2. 解压本压缩包，双击 install.bat。需要管理员权限时会弹出询问，点“是”。
3. 等脚本跑完（首次编译词库约 1 到 2 分钟）。如果它提示没有确认部署完成，在任务栏托盘的小狼毫图标上右键 -> 重新部署。
4. 在任意输入框用 Ctrl+Shift 或 Win+空格 切换到小狼毫。

用法
- 打字试试：zm、jingli。候选后面带 ◇ 表示 Suzu 参与了排序。
- Ctrl+Shift+5 临时开关 AI。

隐私
- 模型和推理都在你的电脑上，输入内容不会上传。
- 选词统计、语料记录、输入事件流这类开发用的功能全部关闭，脚本不会创建它们的开关。
- AI 重排会读取光标前的几个字作为上文，只在内存里使用，不写入任何文件。

还原与卸载
- 安装前的用户目录备份在“用户目录.backup-时间”（默认在 %APPDATA% 下，名字是 Rime.backup-时间），改回原名即可还原。
- 只关闭 AI：退出小狼毫算法服务，删除小狼毫安装目录里的 rime_llm.dll（脚本已把旧文件备份为 rime_llm.dll.bak-时间，没有旧文件则直接删除）。

遇到问题：https://github.com/1zumiii/rime-suzu/issues
