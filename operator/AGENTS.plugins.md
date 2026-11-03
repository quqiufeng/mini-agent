# Plugin AGENTS

- 每个插件：`plugin.json` + `entry/*.sh` + 实现 + `test/`。
- `entry/*.sh` 只透传参数，不写业务分支，不拼用户输入。
- 实现优先 Lua（`lib/core`、`lib/state`、`lib/device`）；C 逻辑经 argv，不 `system/popen`。
- 设备归属用 `tools/device.sh` lease；状态写 `tools/state.sh`。
- 新插件必须：契约测试（成功/坏参数/依赖失败）+ 一次真实证据。
- 禁止直接操作 `/tmp` 业务标记、旧 pid 文件或绕过 policy。
