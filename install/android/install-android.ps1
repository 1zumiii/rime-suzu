# Suzu 一键安装（Android，改版同文输入法 Trime），在 Windows 电脑上运行，手机用 USB 连接。
# 前提：手机上打开“开发者选项”里的“USB 调试”，连上电脑后在手机上点“允许此电脑调试”。
# 用法：双击 install-android.bat（或 powershell -File install-android.ps1 [-DryRun] [-Grammar ask|download|skip]）
# 会做的事：安装改版 Trime -> 推送配置、词库 -> 启动 AI 推理进程。
# 不会做的事：不创建任何统计或记录开关，不联网上传任何东西。
param(
  [switch]$DryRun,
  [ValidateSet('ask', 'download', 'skip')][string]$Grammar = 'ask'   # 万象语法模型（约 400 MB）：询问 / 直接下载 / 不下载
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here "payload"
$Pkg = "com.osfans.trime"
$Rime = "/sdcard/Android/data/$Pkg/files/rime"
$Dir = "/data/local/tmp/rimellm"
if ($DryRun) { $Rime = "/sdcard/Download/suzu-dryrun-rime" }
function Say($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Note($m) { Write-Host "  $m" }
function Fail($m) { Write-Host ""; Write-Host "出错：$m" -ForegroundColor Red; Read-Host "按回车关闭"; exit 1 }
function Pause-Msg($m) { Read-Host "  $m（做完按回车）" | Out-Null }
# 万象语法模型：改善整句输入的同音字选择，改版同文自带 octagram 插件。文件太大不放进安装包，安装时按用户选择从作者的发布页下载到电脑，
# 核对作者公布的 sha256 后推到手机。来源 amzxyz/rime-wanxiang-data（CC BY 4.0）；作者更新文件后要同步更新这里的哈希。
$GramName = 'wanxiang-lts-zh-hans.gram'
$GramUrl = 'https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram'
$GramSha256 = '9eedac1d836f3fdafb61b162035c8937253aedc106be40b2b957d9ab64e9ed89'
# 没有语法模型时去掉配置里的 grammar 块与依赖它的 contextual_suggestions，免得每次部署都报错（与 Windows 安装脚本相同的规则）
function Remove-GrammarConfig($yaml) {
  if (-not (Test-Path $yaml)) { return }
  $t = [IO.File]::ReadAllText($yaml, [Text.Encoding]::UTF8)
  $t = [regex]::Replace($t, '(?m)^[ \t]*#[^\n]*wanxiang[^\n]*\r?\n', '')
  $t = [regex]::Replace($t, '(?m)^([ \t]*)grammar:[ \t]*\r?\n(?:\1[ \t]+[^\n]*\r?\n)*', '')
  $t = [regex]::Replace($t, '(?m)^[ \t]*translator/contextual_suggestions:[^\n]*\r?\n', '')
  [IO.File]::WriteAllText($yaml, $t, (New-Object Text.UTF8Encoding($false)))
}
function Sha256Of($f) { (Get-FileHash $f -Algorithm SHA256).Hash.ToLower() }
if (-not ((Test-Path (Join-Path $Here 'android\trime.apk')) -and (Test-Path $Payload))) { Fail "安装包不完整，请重新解压。" }

Say "Suzu 一键安装（Android）"
# ---- adb ----
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
  $adb = Join-Path $Here '.platform-tools\platform-tools\adb.exe'
  if (-not (Test-Path $adb)) {
    Say "没有找到 adb，下载谷歌官方的 platform-tools（约 7 MB）"
    New-Item -ItemType Directory -Force (Join-Path $Here '.platform-tools') | Out-Null
    $zip = Join-Path $Here '.platform-tools\pt.zip'
    Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath (Join-Path $Here '.platform-tools') -Force
    Remove-Item $zip
  }
}
# adb 把“没有设备”“守护进程启动中”这类提示写到 stderr；Windows PowerShell 5.1 在 $ErrorActionPreference = "Stop" 下会把它当成终止错误，
# 脚本会在给出友好提示之前崩掉，所以调用 adb 时临时改成 Continue。
function Adb { $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { & $adb @args } finally { $ErrorActionPreference = $old } }
function AdbSh([string]$cmd) { $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"; try { (& $adb shell $cmd) -join "`n" } finally { $ErrorActionPreference = $old } }
Adb start-server | Out-Null

Say "1/6 检查手机"
$state = (Adb get-state 2>$null)
if ($state -ne 'device') { Adb devices; Fail "没有可用的手机。请确认：已用 USB 连接；已打开 USB 调试；手机上点了“允许 USB 调试”（可勾选“始终允许”）。多台设备同时连接时请只留一台。" }
$abi = (AdbSh 'getprop ro.product.cpu.abi').Trim()
$sdk = [int](AdbSh 'getprop ro.build.version.sdk').Trim()
Note "设备：$((AdbSh 'getprop ro.product.model').Trim())，API $sdk，$abi"
if ($abi -ne 'arm64-v8a') { Fail "只支持 arm64 手机（当前 $abi）。" }
if ($sdk -lt 30) { Fail "需要 Android 11（API 30）或更新。" }

Say "2/6 安装改版同文输入法"
if ($DryRun) { Note "（试运行，跳过安装）" } else {
  $out = (Adb install -r --user 0 (Join-Path $Here 'android\trime.apk') 2>&1) -join "`n"
  if ($out -notmatch 'Success') {
    if ($out -match 'INCOMPATIBLE|signatures do not match') {
      Note "手机上的同文输入法签名与本安装包不同（比如是应用商店的原版），必须先卸载才能装。卸载会清空它的配置和词库。"
      $yn = Read-Host "  确认卸载原版同文输入法并继续吗？(y/n)"
      if ($yn -ne 'y') { Fail "已取消" }
      Adb shell pm uninstall --user 0 $Pkg | Out-Null
      $out = (Adb install -r --user 0 (Join-Path $Here 'android\trime.apk') 2>&1) -join "`n"
      if ($out -notmatch 'Success') { Fail "安装失败：$out" }
    } else { Fail "APK 安装失败：$out" }
  }
  Note "已安装"
}

Say "3/6 首次启动同文输入法"
if ($DryRun) { Adb shell "mkdir -p $Rime" | Out-Null }
if ((AdbSh "test -d $Rime && echo yes") -notmatch 'yes') {
  Write-Host @"
  请在手机上：
    1) 设置 -> 系统 -> 键盘 -> 屏幕键盘 -> 管理 -> 打开“同文输入法”（不同品牌的位置略有差异）；
    2) 打开同文输入法的应用图标，按引导走完：启用输入法、切换为当前输入法，
       在“存储”一步选择“使用应用专属存储空间”。
"@
  Pause-Msg "完成上面的引导"
  for ($i = 0; $i -lt 60 -and (AdbSh "test -d $Rime && echo yes") -notmatch 'yes'; $i++) { Start-Sleep -Seconds 2 }
  if ((AdbSh "test -d $Rime && echo yes") -notmatch 'yes') { Fail "没有找到同文的用户目录 $Rime。请确认引导已走完且选了“使用应用专属存储空间”。" }
}
Note "同文用户目录已就绪"

Say "4/6 推送配置和词库（约 80 MB）"
if (-not $DryRun -and (AdbSh "test -d $Rime.bak-before-suzu && echo yes") -notmatch 'yes') {
  Adb shell "cp -r $Rime $Rime.bak-before-suzu" | Out-Null; Note "已备份原有配置到 $Rime.bak-before-suzu"
}
$stage = Join-Path ([IO.Path]::GetTempPath()) ('suzu_stage_' + [guid]::NewGuid().ToString('N'))
robocopy $Payload $stage /E /XF suzu.gguf suzu.vocab.txt /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "整理文件失败（robocopy $LASTEXITCODE）" }
if ((AdbSh "grep -q 'schema: rime_ice' $Rime/default.custom.yaml 2>/dev/null && echo yes") -match 'yes') {
  Remove-Item (Join-Path $stage 'default.custom.yaml') -ErrorAction SilentlyContinue; Note "保留手机上现有的 default.custom.yaml"
}
# 语法模型：手机上已有就用；选了下载就先下到电脑（安装包目录里，下次运行不用重下）、核对 sha256 再推到手机；否则去掉配置里的 grammar
$gramOk = $false
$localGram = Join-Path $Here $GramName
if ((AdbSh "test -f $Rime/$GramName && echo yes") -match 'yes') { $gramOk = $true; Note "语法模型：手机上已有 $GramName，直接使用" }
else {
  if ($Grammar -eq 'ask') {
    $Grammar = 'skip'
    if (-not $DryRun) {
      Note "语法模型（可选，约 400 MB）：改善整句输入的同音字选择；不下载也能正常使用，只是整句质量差一点"
      $g = Read-Host "  要下载万象语法模型吗？来自 github.com/amzxyz/rime-wanxiang-data（y/n）"
      if ($g -eq 'y' -or $g -eq 'Y') { $Grammar = 'download' }
    }
  }
  if ($Grammar -eq 'download' -and -not $DryRun) {
    if ((Test-Path $localGram) -and (Sha256Of $localGram) -eq $GramSha256) { Note "使用安装包目录里已下载的语法模型" }
    else {
      Note "正在下载语法模型（约 400 MB，视网速需要几分钟）……"
      $tmp = "$localGram.part"
      Remove-Item $localGram, $tmp -ErrorAction SilentlyContinue
      try {
        $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
        if (Test-Path $curl) { & $curl -L --fail --retry 2 -o $tmp $GramUrl; if ($LASTEXITCODE -ne 0) { throw "curl 返回 $LASTEXITCODE" } }
        else { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri $GramUrl -OutFile $tmp -UseBasicParsing }
        if ((Sha256Of $tmp) -ne $GramSha256) { throw "文件校验不一致（可能是作者更新了文件）" }
        Move-Item $tmp $localGram -Force
        Note "语法模型已下载并校验"
      } catch {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Note "语法模型下载失败：$($_.Exception.Message)。先不用它，之后重新运行安装并选 y 即可。"
      }
    }
    if (Test-Path $localGram) { $gramOk = $true }
  }
}
if (-not $gramOk) { Remove-GrammarConfig (Join-Path $stage 'rime_ice.custom.yaml'); Note "未安装语法模型：已从配置里去掉 grammar（不影响使用）" }
Adb push "$stage\." "$Rime/" | Select-Object -Last 1
if ($gramOk -and (Test-Path $localGram) -and (AdbSh "test -f $Rime/$GramName && echo yes") -notmatch 'yes') {
  Adb push $localGram "$Rime/$GramName.part" | Select-Object -Last 1
  Adb shell "mv $Rime/$GramName.part $Rime/$GramName" | Out-Null
}
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
if ($DryRun) { Say "试运行结束"; Note "已把配置推到 $Rime（临时目录，可删除）。设备检查与文件推送正常。"; exit 0 }

Say "5/6 让同文输入法编译词库"
Write-Host "  请在手机上点开任意输入框，让同文键盘弹出来，并保持手机亮屏（键盘没弹出时，部署指令会被忽略）。"
Pause-Msg "键盘已弹出"
Adb shell "rm -f $Rime/build/rime_ice.table.bin" | Out-Null
Adb shell "am broadcast -a $Pkg.action.DEPLOY -p $Pkg" | Out-Null
Write-Host -NoNewline "  编译词库中（首次约 10 到 30 秒，手机慢的话更久）"
$ok = $false
for ($i = 1; $i -le 90; $i++) {
  Start-Sleep -Seconds 2; Write-Host -NoNewline "."
  if ((AdbSh "test -f $Rime/build/rime_ice.table.bin && test -f $Rime/build/rime_ice.prism.bin && echo yes") -match 'yes') { $ok = $true; break }
  if ($i -eq 8) { Write-Host ""; Write-Host "  还没开始：请确认手机亮屏且键盘正在显示。" }
}
Write-Host ""
if (-not $ok) { Fail "3 分钟内没有编译出词库。请保持键盘弹出后重新运行本脚本。" }
Note "词库已编译"

Say "6/6 启动 AI 推理进程"
Adb shell "mkdir -p $Dir" | Out-Null
Adb shell "pkill -x rimellmd" 2>$null | Out-Null
Start-Sleep -Seconds 1
Adb push (Join-Path $Here 'android\rimellmd') "$Dir/rimellmd" | Select-Object -Last 1
Adb push (Join-Path $Payload 'suzu.gguf') "$Dir/suzu.gguf" | Select-Object -Last 1
Adb push (Join-Path $Payload 'suzu.vocab.txt') "$Dir/suzu.vocab.txt" | Select-Object -Last 1
Adb shell "chmod 755 $Dir/rimellmd" | Out-Null
$startCmd = "( cd $Dir && setsid nohup ./rimellmd --supervise --model $Dir/suzu.gguf --student-vocab $Dir/suzu.vocab.txt --rime-dir $Rime --log-dir $Dir --port 17920 --threads 2 --idle-sec 0 --screen-off-sec 0 --n-seq-max 10 --gen-beam 10 >> $Dir/daemon.log 2>&1 < /dev/null & ) > /dev/null 2>&1 < /dev/null"
Adb shell $startCmd | Out-Null
$started = $false
for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Milliseconds 500; if ((AdbSh "pidof rimellmd") -match '\d') { $started = $true; break } }
if (-not $started) { Fail "AI 推理进程没有启动成功，日志在手机的 $Dir/daemon.log" }
Note "已启动"

Say "安装完成"
Write-Host @"
  1. 在输入框里打 zm 或 jingli，候选后面带 ◇ 表示 Suzu 参与了排序。工具栏的“AI”徽标可以点一下开关。
  2. AI 推理进程在手机重启后会消失，AI 重排随之不生效（打字不受影响）。重启手机后，把手机连电脑，
     再次运行 install-android.bat 即可（已装好的部分会跳过或覆盖为同一版本）。
  3. 选词统计、语料记录这类开发用的功能全部关闭，不会记录你的输入，输入内容也不会上传。
  4. 想还原：卸载本输入法即可；原来的配置备份在手机的 $Rime.bak-before-suzu。
"@
Read-Host "按回车关闭"
