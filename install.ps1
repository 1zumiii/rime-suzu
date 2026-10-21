# Suzu 一行安装（Windows）：下载安装包、校验、解压并运行里面的安装脚本。
#   小狼毫（Windows 输入法）：  irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
#   Android（在 Windows 电脑上，手机用 USB 连接）：
#     $env:SUZU_TARGET='android'; irm https://raw.githubusercontent.com/1zumiii/rime-suzu/main/install.ps1 | iex
# 环境变量：SUZU_TARGET（windows 或 android，默认 windows）；SUZU_BUNDLE_FILE 使用本地的安装包 zip（跳过下载）；
#          SUZU_BASE_URL 指定安装包所在的地址；SUZU_TAG 指定发布标签（默认 preview）。
# 说明：安装包里是已编译好的推理核心、模型、配置和词库，下载后会先核对 sha256 再运行；脚本不会上传任何内容。
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # 进度条会让 Invoke-WebRequest 慢很多
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
$repo = '1zumiii/rime-suzu'
$tag = if ($env:SUZU_TAG) { $env:SUZU_TAG } else { 'preview' }
$base = if ($env:SUZU_BASE_URL) { $env:SUZU_BASE_URL } else { "https://github.com/$repo/releases/download/$tag" }
$target = if ($env:SUZU_TARGET) { $env:SUZU_TARGET } else { 'windows' }
$work = if ($env:SUZU_WORK_DIR) { $env:SUZU_WORK_DIR } else { Join-Path $env:LOCALAPPDATA 'suzu-install' }

switch ($target) {
  'windows' { $asset = 'suzu-windows-x64.zip';   $entry = 'install.ps1' }
  'android' { $asset = 'suzu-android-arm64.zip'; $entry = 'install-android.ps1' }
  default   { Write-Host "不认识的目标：$target（可用 windows 或 android）" -ForegroundColor Red; return }
}
New-Item -ItemType Directory -Force $work | Out-Null
$zip = Join-Path $work $asset
if ($env:SUZU_BUNDLE_FILE) {
  $zip = $env:SUZU_BUNDLE_FILE
  if (-not (Test-Path $zip)) { Write-Host "找不到 $zip" -ForegroundColor Red; return }
} else {
  Write-Host "下载 $asset ……"
  try { Invoke-WebRequest -Uri "$base/$asset" -OutFile "$zip.part" -UseBasicParsing } catch { Write-Host "下载失败：$base/$asset`n安装包可能还没有发布，或网络不通。" -ForegroundColor Red; return }
  # .sha256 按二进制发布时，Windows PowerShell 5.1 的 .Content 是字节数组，先转成文本
  try { $r = Invoke-WebRequest -Uri "$base/$asset.sha256" -UseBasicParsing; $txt = if ($r.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($r.Content) } else { [string]$r.Content }; $want = ($txt.Trim() -split '\s+')[0] } catch { Write-Host "没有找到校验文件 $base/$asset.sha256" -ForegroundColor Red; return }
  $got = (Get-FileHash "$zip.part" -Algorithm SHA256).Hash.ToLower()
  if ($want.ToLower() -ne $got) { Remove-Item "$zip.part" -Force; Write-Host "校验失败：下载的文件与发布的 sha256 不一致，已停止。" -ForegroundColor Red; return }
  Move-Item "$zip.part" $zip -Force
  Write-Host "校验通过（sha256 $($got.Substring(0,12))…）"
}
$dir = Join-Path $work 'bundle'
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
New-Item -ItemType Directory -Force $dir | Out-Null
Expand-Archive -Path $zip -DestinationPath $dir -Force
$inner = Get-ChildItem $dir -Directory | Select-Object -First 1
$script = Join-Path $inner.FullName $entry
if (-not (Test-Path $script)) { Write-Host "安装包里没有 $entry，包不完整。" -ForegroundColor Red; return }
Get-ChildItem $inner.FullName -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
& powershell -NoProfile -ExecutionPolicy Bypass -File $script
