# glyph_scan.ps1 — 找出本机字体画不出的字，写成小狼毫用户目录的 glyph_missing.txt（lua/glyph_guard.lua 读取）。
# 含这些字的候选不再显示（否则候选窗里会画成方框）。装了新字体或升级 Windows 后重跑一次，然后重新部署小狼毫。
#   powershell -NoProfile -ExecutionPolicy Bypass -File windows\glyph_scan.ps1 [-RimeDir D:\AppData\Rime] [-Out <文件>]
# 判断方法：把系统字体目录和当前用户字体目录里所有字体的字符表（cmap）合在一起，任何字体都没有字形的码位算画不出。
#   这比小狼毫实际的字体回退宽松：某个字体有字形，回退时不一定选得到它，所以清单可能漏掉个别画不出的字，但不会误拦画得出的字。
# 另外两条 Windows 专有的规则：
#   1. 区域指示符号 U+1F1E6–1F1FF（国旗表情由两个组成）整段算画不出。Windows 的 Segoe UI Emoji 不支持国旗，
#      候选窗里会画成两个带框的字母。
#   2. 扫描范围与 macOS 的 glyph_scan.swift、Android 的 GlyphScan.kt 一致：符号与表情、CJK 基本区与扩展区、兼容汉字。
param(
  [string]$RimeDir = "",
  [string]$Out = ""
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationCore

if (-not $RimeDir) {
  $reg = Get-ItemProperty HKCU:\Software\Rime\Weasel -ErrorAction SilentlyContinue
  $RimeDir = if ($reg -and $reg.RimeUserDir) { $reg.RimeUserDir } else { Join-Path $env:APPDATA "Rime" }
}
if (-not $Out) { $Out = Join-Path $RimeDir "glyph_missing.txt" }

$ranges = @(
  @(0x2600, 0x27BF), @(0x2B00, 0x2BFF),       # 杂项符号、装饰符号、箭头补充
  @(0x3400, 0x4DBF), @(0x4E00, 0x9FFF),       # 扩展 A、基本区
  @(0xF900, 0xFAFF),                          # 兼容汉字
  @(0x1F000, 0x1FAFF),                        # 表情与符号
  @(0x20000, 0x323AF)                         # 扩展 B 到 H、I，兼容汉字补充
)
$forced = , @(0x1F1E6, 0x1F1FF)              # 区域指示符号（国旗），在表情区间之内。前面的逗号防止 PowerShell 把单元素嵌套数组展平

# 所有字体的 cmap 合集。Fonts.GetTypefaces 传目录时返回目录里全部字体（含 .ttc 的每个字面）。
$have = [System.Collections.Generic.HashSet[int]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new()
$nfaces = 0
foreach ($d in "$env:WINDIR\Fonts\", "$env:LOCALAPPDATA\Microsoft\Windows\Fonts\") {
  if (-not (Test-Path $d)) { continue }
  foreach ($tf in [System.Windows.Media.Fonts]::GetTypefaces([uri]$d)) {
    $g = $null
    try { if (-not $tf.TryGetGlyphTypeface([ref]$g)) { continue } } catch { continue }
    $id = "$($g.FontUri)|$($g.FaceIndex)"
    if (-not $seen.Add($id)) { continue }
    $nfaces++
    try { foreach ($k in $g.CharacterToGlyphMap.Keys) { [void]$have.Add($k) } } catch { }
  }
}

function In-Forced([int]$cp) { foreach ($r in $forced) { if ($cp -ge $r[0] -and $cp -le $r[1]) { return $true } }; return $false }

$lines = [System.Collections.Generic.List[string]]::new()
$total = 0
foreach ($r in $ranges) {
  $start = -1
  for ($cp = $r[0]; $cp -le $r[1]; $cp++) {
    $miss = (In-Forced $cp) -or -not $have.Contains($cp)
    if ($miss) { $total++; if ($start -lt 0) { $start = $cp } }
    if ((-not $miss -or $cp -eq $r[1]) -and $start -ge 0) {
      $end = if ($miss) { $cp } else { $cp - 1 }
      $lines.Add($(if ($start -eq $end) { '{0:X}' -f $start } else { '{0:X}-{1:X}' -f $start, $end }))
      $start = -1
    }
  }
}

$os = (Get-CimInstance Win32_OperatingSystem)
$header = "# 本机字体画不出的字（Windows $($os.Version)，$nfaces 个字面，$(Get-Date -Format s)），由 windows/glyph_scan.ps1 生成"
$body = (@($header) + $lines) -join "`n"
[IO.File]::WriteAllText($Out, $body + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "已写入 ${Out}：画不出 $total 个码位，$($lines.Count) 段（含区域指示符号 26 个）"
