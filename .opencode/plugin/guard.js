// 白名单兜底：brain 只允许单条 tools/*.sh 或 plugins/**/*.sh，禁止 shell 拼接
export const Guard = async () => ({
  "tool.execute.before": async (input, output) => {
    if (process.env.AGENT_BRAIN !== "1") return
    const tool = input?.tool ?? input?.name
    if (tool !== "bash") return
    const cmd = String(output?.args?.command ?? "").trim()
    const entry = String.raw`(?:tools/[a-z0-9_-]+\.sh|plugins/(?:[a-z0-9_-]+/)+[a-z0-9_.-]+\.sh|temp/(?:[a-z0-9_-]+/)+[a-z0-9_.-]+\.sh)`
    const re = new RegExp(`^(?:(?:/home/quqiufeng/my-agent(?:/operator)?/)?(?:\\./)?${entry})(?: [^;&|\`$<>(){}]*)?$`)
    if (!re.test(cmd)) {
      throw new Error("命令被白名单拦截（只允许单条 tools/*.sh 或 plugins/* 入口，禁止拼接与重定向）: " + cmd)
    }
  },
})
