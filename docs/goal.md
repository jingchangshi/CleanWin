请在当前目录创建一个 Windows 11 内存诊断与安全清理工具，目标用户主要使用 Edge、WSL2、Docker、VSCode/Cursor、AI 编译开发环境。

要求：

1. 使用 PowerShell 实现，兼容 Windows 11。
2. 创建以下文件：
   - diagnose-memory.ps1
   - clean-memory.ps1
   - config.json
   - README.md

3. diagnose-memory.ps1 功能：
   - 显示总内存、已用内存、可用内存、内存使用率。
   - 显示 Top 15 内存占用进程，包含进程名、PID、内存 GB。
   - 检查 WSL 是否有正在运行的发行版。
   - 检查是否存在 vmmem、vmmemWSL、Docker Desktop、com.docker.backend、msedge、Code、Cursor 等进程。
   - 提示可能的内存来源：WSL、Docker、Edge、IDE、Standby Cache、驱动泄漏。
   - 不执行任何清理操作。

4. clean-memory.ps1 功能：
   - 默认执行安全清理：
     a. wsl --shutdown
     b. 关闭 Edge 后台进程
     c. 清理用户临时目录
     d. 清理 Windows Temp
     e. 显示清理前后内存使用情况
   - 所有危险操作必须二次确认，包括：
     a. 关闭 Docker Desktop
     b. 停止 Hyper-V 相关服务
     c. 清空回收站
     d. 清理 Windows Update 缓存
   - 不要默认删除用户文件。
   - 不要默认 compact WSL vhdx。
   - 每一步需要有清晰日志输出。
   - 发生错误时继续执行后续步骤，但打印 warning。

5. config.json：
   - allowKillEdge: true
   - allowShutdownWSL: true
   - allowCleanTemp: true
   - allowKillDocker: false
   - allowEmptyRecycleBin: false
   - allowCleanWindowsUpdateCache: false

6. README.md：
   - 说明使用方式。
   - 说明普通用户推荐先运行 diagnose-memory.ps1。
   - 说明 clean-memory.ps1 默认是安全清理。
   - 说明可能需要管理员权限。
   - 说明不会默认删除用户文件。
   - 说明 WSL2 内存占用高时可通过 wsl --shutdown 释放。
   - 说明 Standby Cache 不一定是问题。

7. 代码风格：
   - PowerShell 代码要有函数封装。
   - 所有路径操作要做好异常处理。
   - 输出要清晰，适合中文 Windows 用户使用。
   - 不依赖第三方模块。

