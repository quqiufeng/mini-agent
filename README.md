# my-agent（本地最小子集）

本地版的 tmux + opencode 大脑，只保留 remote `/opt/my-agent` 的最核心结构：

```
tmux session: local-my-agent
├─ window "serve": opencode serve --port 4097
└─ window "tui":   opencode attach http://127.0.0.1:4097
```

`opencode` 的工作目录固定为 `~/my-agent`，启动时会自动读取 `~/my-agent/AGENTS.md`，因此它知道本机/远程的能力和调用方式。

## 用法

```bash
cd ~/my-agent

./start.sh            # 启动并 attach
./start.sh --bg       # 只后台启动
./status.sh           # 查看 session / 窗口 / 4097 健康状态
./send.sh "现在几点"   # 通过 /tui 接口向大脑提交一条消息
./stop.sh             # 停止
```

端口可用 `AGENT_PORT` 覆盖，session 名可用 `AGENT_SESSION` 覆盖。

## 文件

| 文件 | 用途 |
|---|---|
| `start.sh` | 幂等启动 serve + tui，可选 attach |
| `stop.sh` | 停止 tmux session |
| `status.sh` | 查看运行状态和健康检查 |
| `send.sh` | POST `/tui/append-prompt` + `/tui/submit-prompt` |

## 与 remote my-agent 的差异

- 这是**最小大脑运行时**，不包含 remote 的 `operator/tools` 白名单、`guard.js`、语音/微信入口和心跳。
- 本地 opencode 的权限由 `~/.config/opencode/opencode.json` 决定，默认比 remote 宽；真正的重活仍应调用 `AGENTS.md` 里记录的远程能力。
