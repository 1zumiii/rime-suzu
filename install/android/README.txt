Suzu 一键安装（Android）

适用：arm64 的 Android 11 或更新的手机；一台电脑（macOS、Linux 或 Windows），一根 USB 线。

准备
1. 手机：设置 -> 关于手机 -> 连点“版本号”七次打开开发者模式；开发者选项里打开“USB 调试”。
2. 用 USB 连接电脑，手机上弹出“允许 USB 调试”时点允许（可勾选“始终允许”）。
3. 如果手机上装过应用商店的原版同文输入法：脚本会提示先卸载（会清空它的配置），确认后继续。

步骤
- macOS 或 Linux：解压后在终端里进入文件夹，运行 bash install-android.sh
- Windows：解压后双击 install-android.bat
脚本会：下载 adb（没有的话）、安装改版同文输入法、让你在手机上走一遍首次引导（“存储”一步选“使用应用专属存储空间”）、推送配置和词库、编译词库、启动 AI 推理进程。
先加参数 --dry-run（Windows 用 -DryRun）可以只检查手机，不安装不部署。

用法
- 输入法切换到同文，打 zm、jingli。候选后面带 ◇ 表示 Suzu 参与了排序，工具栏的“AI”徽标可以点一下开关。
- 手机重启后，AI 推理进程会消失（打字不受影响，只是 AI 不再重排）。重启后把手机连电脑，macOS 或 Linux 运行 bash restart-daemon.sh，Windows 再运行一次 install-android.bat。

隐私
- 模型和推理都在你的手机上，输入内容不会上传。
- 选词统计、语料记录、输入事件流这类开发用的功能全部关闭，脚本不会创建它们的开关。

还原与卸载
- 卸载改版同文输入法即可；原来的配置备份在手机的 Android/data/com.osfans.trime/files/rime.bak-before-suzu。

遇到问题：https://github.com/1zumiii/rime-suzu/issues
