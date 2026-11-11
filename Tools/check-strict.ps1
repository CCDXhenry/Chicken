param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Files,

    [switch]$Staged,
    [switch]$All
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$RootDir = (Resolve-Path "$PSScriptRoot\..").Path
$DefsPath = "$RootDir\Tools\globalTypes.d.luau"
$SourcemapPath = "$RootDir\sourcemap.json"

# 1. 查找全局类型定义文件
if (-not (Test-Path $DefsPath)) {
    $CursorDefs = "$env:APPDATA\Cursor\User\globalStorage\johnnymorganz.luau-lsp\globalTypes.PluginSecurity.d.luau"
    $VsCodeDefs = "$env:APPDATA\Code\User\globalStorage\johnnymorganz.luau-lsp\globalTypes.PluginSecurity.d.luau"
    if (Test-Path $CursorDefs) {
        $DefsPath = $CursorDefs
    } elseif (Test-Path $VsCodeDefs) {
        $DefsPath = $VsCodeDefs
    } else {
        Write-Error "未找到 globalTypes.d.luau 类型定义文件，请先在 Tools/globalTypes.d.luau 放置类型定义。"
        exit 1
    }
}

# 2. 收集目标检测文件
$TargetFiles = @()

if ($Files -and $Files.Count -gt 0) {
    foreach ($f in $Files) {
        $fullPath = Resolve-Path $f -ErrorAction SilentlyContinue
        if ($fullPath -and (Test-Path $fullPath.Path)) {
            $TargetFiles += $fullPath.Path
        }
    }
} elseif ($All) {
    # 全量扫描 Scripts 目录下所有 .luau 文件
    $scriptsDir = "$RootDir\Scripts"
    if (Test-Path $scriptsDir) {
        Get-ChildItem -Path $scriptsDir -Filter "*.luau" -Recurse -File | ForEach-Object {
            $TargetFiles += $_.FullName
        }
    }
} else {
    Push-Location $RootDir
    try {
        if ($Staged) {
            $gitOutput = git diff --cached --name-only --diff-filter=ACM
        } else {
            $gitOutput = git status --porcelain --untracked-files=all | ForEach-Object {
                $raw = $_
                if ($raw.Length -gt 3) {
                    $raw.Substring(3).Trim()
                }
            }
        }
        foreach ($rel in $gitOutput) {
            if ($rel -and $rel.EndsWith(".luau")) {
                $full = Join-Path $RootDir $rel
                if (Test-Path $full) {
                    $TargetFiles += $full
                }
            }
        }
    } finally {
        Pop-Location
    }
}

if ($TargetFiles.Count -eq 0) {
    Write-Host "没有检测到需要分析的 .luau 目标文件。" -ForegroundColor Green
    exit 0
}

# 3. 过滤需要严格检查的脚本（包含 --!strict 且非豁免目录）
$StrictFiles = @()
foreach ($file in $TargetFiles) {
    $normalized = $file.Replace("\", "/")
    # 豁免第三方库，以及配表插件生成的 GameConfig/*Data.luau；init.luau 仍检查
    if ($normalized -match "GameAnalytics" -or $normalized -match "/GameConfig/[^/]+Data\.luau$") {
        continue
    }

    try {
        # 支持第一行或第二行声明 --!strict（兼容首行业务中文注释规范）
        $lines = Get-Content -Path $file -TotalCount 2 -ErrorAction Stop
        $hasStrict = $false
        foreach ($line in $lines) {
            if ($line.Trim() -eq "--!strict") {
                $hasStrict = $true
                break
            }
        }
        if ($hasStrict) {
            $StrictFiles += $file
        }
    } catch {
    }
}

if ($StrictFiles.Count -eq 0) {
    Write-Host "检测的文件中没有需要进行严格模式检查的脚本（无 --!strict 或已在豁免名单中）。" -ForegroundColor Green
    exit 0
}

# 4. 自动生成或更新 sourcemap.json
function Get-ChickenSourcemapNode($dirPath, $nodeName, $defaultClassName) {
    $initFile = Get-ChildItem -Path $dirPath -Filter "init*.luau" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $isModule = ($null -ne $initFile)
    
    $node = [PSCustomObject]@{
        name = $nodeName
        className = if ($isModule) { "ModuleScript" } else { $defaultClassName }
        children = @()
    }
    if ($isModule) {
        $node | Add-Member -MemberType NoteProperty -Name "filePaths" -Value @($initFile.FullName.Replace('\', '/'))
    }
    
    foreach ($item in (Get-ChildItem -Path $dirPath -ErrorAction SilentlyContinue)) {
        if ($item.PSIsContainer) {
            $node.children += Get-ChickenSourcemapNode $item.FullName $item.Name "Folder"
        } elseif ($item.Extension -eq ".luau" -and (-not $item.Name.StartsWith("init"))) {
            $baseName = $item.BaseName
            if ($baseName -match "\.(legacy|server|client|local)$") {
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($baseName)
            }
            $className = if ($item.Name -match "\.(local|client)\.luau$") {
                "LocalScript"
            } elseif ($item.Name -match "\.(server|legacy)\.luau$") {
                "Script"
            } else {
                "ModuleScript"
            }
            $node.children += [PSCustomObject]@{
                name = $baseName
                className = $className
                filePaths = @($item.FullName.Replace('\', '/'))
            }
        }
    }
    return $node
}

$scriptsDir = "$RootDir\Scripts"
$sm = [PSCustomObject]@{
    name = "game"
    className = "DataModel"
    children = @()
}

$services = @("ReplicatedFirst", "ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayer")
foreach ($srv in $services) {
    $srvDir = Join-Path $scriptsDir $srv
    if (Test-Path $srvDir) {
        $sm.children += Get-ChickenSourcemapNode $srvDir $srv $srv
    }
}

$smJson = $sm | ConvertTo-Json -Depth 25
Set-Content -Path $SourcemapPath -Value $smJson -Encoding UTF8

Write-Host "正在使用 luau-lsp analyze 检测 $($StrictFiles.Count) 个 --!strict 文件..." -ForegroundColor Cyan

# 5. 执行分析
$analyzeArgs = @("analyze")
if (Test-Path $DefsPath) {
    $analyzeArgs += "--defs=$DefsPath"
}
if (Test-Path $SourcemapPath) {
    $analyzeArgs += "--sourcemap=$SourcemapPath"
}
$analyzeArgs += $StrictFiles

$rawOutput = & luau-lsp @analyzeArgs 2>&1

# 6. 精准过滤报错（仅阻断目标文件错误，外部存量依赖警告做提示）
$targetErrors = @()
$otherErrorCount = 0

foreach ($line in $rawOutput) {
    $lineStr = $line.ToString()
    if ($lineStr -match "TypeError:" -or $lineStr -match "SyntaxError:" -or $lineStr -match "LocalShadow:") {
        $matchedTarget = $false
        foreach ($sf in $StrictFiles) {
            $normSf = $sf.Replace("/", "\").ToLower()
            $normLine = $lineStr.Replace("/", "\").ToLower()

            $relSf = $normSf
            $normRoot = $RootDir.Replace("/", "\").ToLower().TrimEnd("\") + "\"
            if ($relSf.StartsWith($normRoot)) {
                $relSf = $relSf.Substring($normRoot.Length)
            }

            $baseSf = [System.IO.Path]::GetFileName($normSf)

            if ($normLine.StartsWith($normSf) -or $normLine.Contains($normSf) -or
                $normLine.StartsWith($relSf) -or $normLine.Contains($relSf) -or
                ($baseSf -and $baseSf -ne "init.luau" -and $normLine.Contains($baseSf))) {
                $targetErrors += $lineStr
                $matchedTarget = $true
                break
            }
        }
        if (-not $matchedTarget) {
            $otherErrorCount++
        }
    }
}

if ($targetErrors.Count -gt 0) {
    Write-Host "检测到 $($targetErrors.Count) 个目标文件类型错误：" -ForegroundColor Red
    foreach ($err in $targetErrors) {
        Write-Host "  $err" -ForegroundColor Red
    }
    Write-Host "存在类型错误，检测未通过！" -ForegroundColor Red
    exit 1
} else {
    if ($otherErrorCount -gt 0) {
        Write-Host "提示：检测到 $otherErrorCount 处来自依赖模块（非本次目标文件）的既有类型警告，已被门禁忽略。" -ForegroundColor Yellow
    }
    Write-Host "所有目标 --!strict 文件类型检测通过！(0 Error)" -ForegroundColor Green
    exit 0
}

