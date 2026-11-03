# Runtime AGENTS

- 单脑：只通过 `plugins/*/entry/*.sh` 或 `tools/devctl.sh` 操作设备。
- 状态只读 `tools/state.sh` / `~/.myagent/state/`；设备只读 `tools/device.sh`。
- 每次动作给出证据（日志/截图/OCR/state），失败按工具规则重试，不拼任意 shell。
- 播放/暂停/切歌优先 `tools/devctl.sh media ...`；手机/微信走 `plugins/phone|wechat`。
- 会话上下文走 `tools/session.sh`（kvcache，TTL）。
- 禁止直接 `adb`/`pactl`/VLC MPRIS 自行判断设备状态。
