# CleanWin

Windows 11 内存诊断与安全清理工具，适合主要使用 Edge、WSL2、Docker、VSCode/Cursor、AI 编译开发环境的用户。

## 文件说明

- `diagnose-memory.ps1`：只诊断，不执行任何清理操作。
- `clean-memory.ps1`：执行默认安全清理，并在危险操作前要求确认。
- `config.json`：控制清理动作是否允许执行。

## 推荐使用方式

普通用户建议先运行诊断脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\diagnose-memory.ps1
```

确认主要内存来源后，再运行安全清理脚本：

```powershell
powershell -ExecutionPolicy Bypass -File .\clean-memory.ps1
```

部分操作可能需要管理员权限，尤其是清理 `C:\Windows\Temp`、停止服务、清理 Windows Update 缓存等。

## 默认安全清理会做什么

`clean-memory.ps1` 默认执行：

- `wsl --shutdown`，释放 WSL2 / vmmem / vmmemWSL 相关内存。
- 关闭 Edge 后台进程。
- 清理当前用户临时目录。
- 清理 Windows Temp。
- 显示清理前后的内存使用情况。

脚本发生错误时会继续执行后续步骤，并打印 warning。

## 默认不会做什么

脚本不会默认删除用户文件，也不会默认 compact WSL vhdx。

以下操作属于危险操作，必须在 `config.json` 中开启，并在运行时输入 `YES` 二次确认：

- 关闭 Docker Desktop。
- 清空回收站。
- 清理 Windows Update 缓存。

停止 Hyper-V 相关服务也属于危险操作，不会在默认流程中执行。只有主动传入参数时才会进入二次确认：

```powershell
powershell -ExecutionPolicy Bypass -File .\clean-memory.ps1 -IncludeHyperVServices
```

## 配置

默认配置：

```json
{
  "allowKillEdge": true,
  "allowShutdownWSL": true,
  "allowCleanTemp": true,
  "allowKillDocker": false,
  "allowEmptyRecycleBin": false,
  "allowCleanWindowsUpdateCache": false
}
```

如果不想关闭 Edge 或 WSL，可以把对应值改为 `false`。

## 说明

WSL2 内存占用高时，通常可以通过 `wsl --shutdown` 释放。再次打开 Linux 终端、Docker 或依赖 WSL 的工具时，WSL 会重新启动。

Standby Cache 是 Windows 正常的缓存机制，不一定是问题。系统会在应用需要内存时自动回收这部分缓存。
