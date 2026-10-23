# Suzu 一键安装（Windows，小狼毫 Weasel 0.17）
# 用法：双击 install.bat。需要管理员权限时会弹出 UAC 询问。
# 会做的事：备份现有用户目录 -> 安装配置、词库、Suzu 模型 -> 把推理核心 rime_llm.dll 放进小狼毫目录 -> 重新部署。
# 不会做的事：不创建任何统计或记录开关（选词统计、语料、输入事件流都保持关闭），不联网上传任何东西。
param(
  [string]$WeaselDir = "",
  [string]$UserDir = "",
  [switch]$Yes,         # 不再询问，直接安装（环境变量 SUZU_YES=1 同效）
  [switch]$DryRun,      # 只检查并列出将要做的事，不改动任何东西
  [switch]$SkipServer,  # 测试用：不停止、不启动小狼毫服务，不重新部署
  [ValidateSet('ask', 'download', 'skip')][string]$Grammar = 'ask'   # 万象语法模型（约 400 MB）：询问 / 直接下载 / 不下载
)
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Payload = Join-Path $Here "payload"
$Dll = Join-Path $Here "core\rime_llm.dll"
function Say($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Note($m) { Write-Host "  $m" }
function Fail($m) { Write-Host ""; Write-Host "出错：$m" -ForegroundColor Red; Read-Host "按回车关闭"; exit 1 }
# 万象语法模型：改善整句输入的同音字选择，小狼毫自带 octagram 插件。文件太大不放进安装包，安装时按用户选择从作者的发布页下载。
# 来源 amzxyz/rime-wanxiang-data（CC BY 4.0）。下载后核对作者公布的 sha256，对不上就不用（作者更新文件后要同步更新这里的哈希）。
$GramName = 'wanxiang-lts-zh-hans.gram'
$GramUrl = 'https://github.com/amzxyz/rime-wanxiang-data/releases/download/LTS/wanxiang-lts-zh-hans.gram'
$GramSha256 = '9eedac1d836f3fdafb61b162035c8937253aedc106be40b2b957d9ab64e9ed89'
# 没有语法模型时去掉配置里的 grammar 块与依赖它的 contextual_suggestions，免得每次部署都报错
function Remove-GrammarConfig($yaml) {
  if (-not (Test-Path $yaml)) { return }
  $t = [IO.File]::ReadAllText($yaml, [Text.Encoding]::UTF8)
  $t = [regex]::Replace($t, '(?m)^[ \t]*#[^\n]*wanxiang[^\n]*\r?\n', '')
  $t = [regex]::Replace($t, '(?m)^([ \t]*)grammar:[ \t]*\r?\n(?:\1[ \t]+[^\n]*\r?\n)*', '')
  $t = [regex]::Replace($t, '(?m)^[ \t]*translator/contextual_suggestions:[^\n]*\r?\n', '')
  [IO.File]::WriteAllText($yaml, $t, (New-Object Text.UTF8Encoding($false)))
}

Say "Suzu 一键安装（Windows）"
if (-not ((Test-Path $Payload) -and (Test-Path $Dll))) { Fail "安装包不完整：找不到 payload 或 core\rime_llm.dll，请重新解压。" }
if (-not [Environment]::Is64BitOperatingSystem) { Fail "只支持 64 位 Windows。" }

# ---- 找到小狼毫 ----
if (-not $WeaselDir) {
  foreach ($k in 'HKLM:\SOFTWARE\WOW6432Node\Rime\Weasel', 'HKLM:\SOFTWARE\Rime\Weasel') {
    $v = (Get-ItemProperty $k -ErrorAction SilentlyContinue).WeaselRoot
    if ($v -and (Test-Path (Join-Path $v 'WeaselServer.exe'))) { $WeaselDir = $v; break }
  }
}
if (-not $WeaselDir) {
  foreach ($base in "$env:ProgramFiles\Rime", "${env:ProgramFiles(x86)}\Rime") {
    if (Test-Path $base) {
      $c = Get-ChildItem $base -Directory -Filter 'weasel-*' | Sort-Object Name -Descending | Select-Object -First 1
      if ($c -and (Test-Path (Join-Path $c.FullName 'WeaselServer.exe'))) { $WeaselDir = $c.FullName; break }
    }
  }
}
if (-not $WeaselDir) { Fail "没有找到小狼毫。请先安装小狼毫 0.17：https://github.com/rime/weasel/releases ，装好后再运行本脚本；装在非默认位置的话，用 install.bat 之外的方式运行：powershell -File install.ps1 -WeaselDir 路径" }
$Server = Join-Path $WeaselDir 'WeaselServer.exe'
$Deployer = Join-Path $WeaselDir 'WeaselDeployer.exe'
Note "小狼毫目录：$WeaselDir"
if ((Split-Path $WeaselDir -Leaf) -notmatch '0\.17') { Note "提示：测试过的是 0.17.x，当前目录名是 $(Split-Path $WeaselDir -Leaf)，其他版本未验证。" }

# ---- 用户目录 ----
if (-not $UserDir) {
  $UserDir = (Get-ItemProperty 'HKCU:\Software\Rime\Weasel' -ErrorAction SilentlyContinue).RimeUserDir
  if (-not $UserDir) { $UserDir = Join-Path $env:APPDATA 'Rime' }
}
Note "用户目录：$UserDir"

# ---- 确认 ----
Say "将要做的事"
Note "1. 把现有用户目录整个备份到 $UserDir.backup-时间"
Note "2. 退出小狼毫服务，安装配置、词库和 Suzu 模型到 $UserDir（不覆盖你的样式、词频库和已有的 default.custom.yaml）"
Note "3. 把推理核心 rime_llm.dll 放进 $WeaselDir（旧的先备份），重新启动服务并部署"
Note "不会创建任何统计或记录开关，不上传任何内容。"
$haveGram = Test-Path (Join-Path $UserDir $GramName)
if ($haveGram) { Note "语法模型：用户目录里已有 $GramName，直接使用" }
else { Note "语法模型（可选，约 400 MB）：改善整句输入的同音字选择；不下载也能正常使用，只是整句质量差一点" }
if ($DryRun) { Say "试运行结束，没有改动任何东西。"; exit 0 }
$interactive = -not ($Yes -or $env:SUZU_YES -eq '1' -or $SkipServer)
if ($interactive) {
  $ans = Read-Host "确认安装吗？(y/n)"
  if ($ans -ne 'y' -and $ans -ne 'Y') { Write-Host "已取消，没有改动任何东西。"; exit 0 }
}
# 语法模型的选择在这里定下来（以管理员身份重新运行时原样传过去，不再问第二遍）；不询问的方式运行时默认不下载
if ($haveGram) { $Grammar = 'skip' }
elseif ($Grammar -eq 'ask') {
  if ($interactive) {
    $g = Read-Host "要下载万象语法模型吗？约 400 MB，来自 github.com/amzxyz/rime-wanxiang-data（y/n）"
    $Grammar = if ($g -eq 'y' -or $g -eq 'Y') { 'download' } else { 'skip' }
  } else { $Grammar = 'skip' }
}

# ---- 需要管理员权限时重新以管理员运行（小狼毫通常装在 Program Files 下） ----
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$canWrite = $false
try { $probe = Join-Path $WeaselDir ('.suzu_write_test_' + [guid]::NewGuid().ToString('N')); New-Item -ItemType File $probe -ErrorAction Stop | Out-Null; Remove-Item $probe; $canWrite = $true } catch {}
if (-not $canWrite -and -not $isAdmin) {
  Note "写入小狼毫目录需要管理员权限，正在请求……"
  $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$($MyInvocation.MyCommand.Path)`"", '-WeaselDir', "`"$WeaselDir`"", '-Yes')
  $argList += @('-UserDir', "`"$UserDir`"", '-Grammar', $Grammar)
  if ($SkipServer) { $argList += '-SkipServer' }
  Start-Process powershell -Verb RunAs -ArgumentList $argList
  exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
New-Item -ItemType Directory -Force $UserDir | Out-Null

function Server-Running { [bool](Get-Process -Name WeaselServer -ErrorAction SilentlyContinue) }
function Stop-Server {
  if (-not (Server-Running)) { return }
  & $Server /q | Out-Null
  for ($i = 0; $i -lt 40 -and (Server-Running); $i++) { Start-Sleep -Milliseconds 500 }
  if (Server-Running) { Fail "小狼毫服务没有在 20 秒内退出。请在任务栏托盘右键小狼毫 -> 退出算法服务，再重新运行。" }
}
# 用“交互式计划任务”启动：服务运行在当前登录用户的桌面会话里，权限不是管理员（管理员权限的服务会和普通程序对不上）
function Start-Unelevated($exe, $arg, $name) {
  $act = if ($arg) { New-ScheduledTaskAction -Execute $exe -Argument $arg -WorkingDirectory $WeaselDir } else { New-ScheduledTaskAction -Execute $exe -WorkingDirectory $WeaselDir }
  $pri = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskName $name -Action $act -Principal $pri -Force | Out-Null
  Start-ScheduledTask -TaskName $name
}

Say "1/5 备份现有用户目录"
$Backup = "$UserDir.backup-$stamp"
robocopy $UserDir $Backup /E /R:1 /W:1 /XD build /XF *.gram *.gguf /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 16) { Fail "备份失败（robocopy 返回 $LASTEXITCODE）" }
Note "已备份到 $Backup（想还原时把它改回 $UserDir 的名字即可）"

if (-not $SkipServer) { Say "2/5 退出小狼毫服务"; Stop-Server } else { Say "2/5 （测试模式，跳过）" }

Say "3/5 安装配置、词库和 Suzu 模型"
# 不覆盖：用户自己的样式、词频库、安装信息、短语和已有的 default.custom.yaml
$xf = @('user.yaml', 'installation.yaml', 'weasel.yaml', 'weasel.custom.yaml', 'custom_phrase.txt', 'default.custom.yaml')
robocopy $Payload $UserDir /E /R:1 /W:1 /XD '*.userdb' sync /XF @xf /NFL /NDL /NJH /NJS | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "复制配置失败（robocopy 返回 $LASTEXITCODE）。请先退出小狼毫服务后重试。" }
$cp = Join-Path $UserDir 'custom_phrase.txt'
if (-not (Test-Path $cp)) { Copy-Item (Join-Path $Payload 'custom_phrase.txt') $cp }
$dc = Join-Path $UserDir 'default.custom.yaml'
if ((Test-Path $dc) -and (Select-String -Path $dc -Pattern 'schema: rime_ice' -SimpleMatch -Quiet)) { Note "保留你现有的 default.custom.yaml（已包含 rime_ice）" }
else { Copy-Item (Join-Path $Payload 'default.custom.yaml') $dc -Force }
Note "配置、词库和模型已就位"
# 语法模型：已有就用；选了下载就下到临时文件、核对 sha256 后再放进用户目录；否则去掉配置里的 grammar
$gram = Join-Path $UserDir $GramName
$gramOk = Test-Path $gram
if (-not $gramOk -and $Grammar -eq 'download') {
  Note "正在下载语法模型（约 400 MB，视网速需要几分钟）……"
  $tmp = "$gram.download"
  Remove-Item $tmp -ErrorAction SilentlyContinue
  try {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    if (Test-Path $curl) { & $curl -L --fail --retry 2 -o $tmp $GramUrl; if ($LASTEXITCODE -ne 0) { throw "curl 返回 $LASTEXITCODE" } }
    else { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri $GramUrl -OutFile $tmp -UseBasicParsing }
    $h = (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
    if ($h -ne $GramSha256) { throw "文件校验不一致（可能是作者更新了文件）" }
    Move-Item $tmp $gram -Force
    $gramOk = $true
    Note "语法模型已下载并校验"
  } catch {
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Note "语法模型下载失败：$($_.Exception.Message)。先不用它，之后可以手动下载 $GramName 放进 $UserDir，再重新运行安装（安装会把配置里的 grammar 加回来）。"
  }
}
if ($gramOk) { if ($Grammar -ne 'download') { Note "使用已有的语法模型" } }
else { Remove-GrammarConfig (Join-Path $UserDir 'rime_ice.custom.yaml'); Note "未安装语法模型：已从配置里去掉 grammar（不影响使用）" }

Say "4/5 安装推理核心"
$live = Join-Path $WeaselDir 'rime_llm.dll'
if (Test-Path $live) { Copy-Item $live "$live.bak-$stamp" -Force; Note "旧的核心已备份为 rime_llm.dll.bak-$stamp" }
Copy-Item $Dll $live -Force
Note "推理核心已安装"

if (-not $SkipServer) {
  Say "5/5 启动并重新部署（首次编译词库，约 1 到 2 分钟）"
  Start-Unelevated $Server '' 'SuzuWeaselStart'
  for ($i = 0; $i -lt 60 -and -not (Server-Running); $i++) { Start-Sleep -Milliseconds 500 }
  Unregister-ScheduledTask -TaskName 'SuzuWeaselStart' -Confirm:$false -ErrorAction SilentlyContinue
  if (-not (Server-Running)) { Fail "小狼毫服务没有启动。请从开始菜单手动启动“小狼毫算法服务”，再在托盘图标上右键 -> 重新部署。" }
  Start-Sleep -Seconds 3
  foreach ($n in 'rime_ice.schema.yaml', 'default.yaml') { Remove-Item (Join-Path $UserDir ('build\' + $n)) -ErrorAction SilentlyContinue }
  $f = Join-Path $UserDir 'build\rime_ice.schema.yaml'
  $t0 = Get-Date
  Start-Unelevated $Deployer '/deploy' 'SuzuWeaselDeploy'
  $done = $false
  for ($i = 0; $i -lt 100 -and -not $done; $i++) {
    Start-Sleep -Seconds 3
    $done = (Test-Path $f) -and ((Get-Item $f).LastWriteTime -gt $t0)
  }
  Start-Sleep -Seconds 2
  Unregister-ScheduledTask -TaskName 'SuzuWeaselDeploy' -Confirm:$false -ErrorAction SilentlyContinue
  if ($done) { Note "已部署" } else { Note "自动部署没有确认完成：请在任务栏托盘图标上右键 -> 重新部署，等它提示完成。" }
} else { Say "5/5 （测试模式，跳过）" }

Say "安装完成"
Write-Host @"
  1. 在任意输入框用 Ctrl+Shift 或 Win+空格 切换到小狼毫，打 zm 或 jingli 试试。候选后面带 ◇ 表示 Suzu 参与了排序。
  2. 临时开关 AI：Ctrl+Shift+5。输入内容全部在本机处理，不会上传。
  3. 选词统计、语料记录这类开发用的功能全部关闭，不会记录你的输入。
  4. 想退回原样：把 $Backup 改回 $UserDir 的名字；只关闭 AI 的话，删除 $WeaselDir\rime_llm.dll（先退出小狼毫服务）。
"@
if (-not $gramOk) { Write-Host "  5. 以后想加语法模型：重新运行安装并在询问时选 y，或手动下载 $GramName 放进 $UserDir 后重新运行安装。" }
if (-not $SkipServer) { Read-Host "按回车关闭" }
