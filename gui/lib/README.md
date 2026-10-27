# gui/lib — 随程序分发的共享库

- `libxdo.so.3`：来自 `xdotool` / `libxdo3`（MIT 许可），随程序一起分发，
  避免目标系统没有安装 `libxdo3` 时 LuaJIT FFI 加载失败。
- 运行时不通过系统路径查找：`gui/sdl/myagent-voice` 带 `RUNPATH=$ORIGIN/../lib`，
  `gui/launch.sh` 与 `tools/lua.sh` 也会把本目录加入 `LD_LIBRARY_PATH`。

升级方式（构建机上）：

```bash
cp /usr/lib/x86_64-linux-gnu/libxdo.so.3 gui/lib/
make -C gui/sdl
```

`libxdo.so.3` 只依赖常见桌面库：`libX11`、`libXtst`、`libXinerama`、`libxkbcommon`、`libc`。
