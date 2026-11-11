# 玩家出生视角与面朝方向摄像机离线回归：执行几何数学、朝向对齐、序列通知与控制器生命周期检查
$ErrorActionPreference = 'Stop'
Push-Location (Resolve-Path "$PSScriptRoot/../..")
try {
    lune run Tools/Tests/CameraSpawnRegression.luau
    if ($LASTEXITCODE -ne 0) { throw 'CameraSpawnRegression failed' }
} finally { Pop-Location }
