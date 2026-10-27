CC ?= gcc
ROOT ?= /home/quqiufeng/my-agent
LUAJIT_INC ?= /usr/include/luajit-2.1
LUAJIT_A ?= $(firstword $(wildcard \
  /usr/lib/x86_64-linux-gnu/libluajit-5.1.a \
  /usr/lib/libluajit-5.1.a \
  /usr/local/lib/libluajit-5.1.a))

ifeq ($(LUAJIT_A),)
$(error LuaJIT static archive not found; install libluajit-5.1-dev or set LUAJIT_A=/path/libluajit-5.1.a)
endif

SDL_CFLAGS := $(shell pkg-config --cflags sdl2 SDL2_ttf SDL2_image)
SDL_LIBS := $(shell pkg-config --libs sdl2 SDL2_ttf SDL2_image)
SDL_STATIC_DEPS := $(shell pkg-config --static --libs sdl2 SDL2_ttf SDL2_image \
  | sed -e 's/-lSDL2_ttf//g' -e 's/-lSDL2_image//g' -e 's/-lSDL2\b//g')

RPATH := -Wl,-rpath,'$$ORIGIN/../lib'
LIBXDO ?= ../lib/libxdo.so.3

CFLAGS := -O2 -Wall -I$(LUAJIT_INC) $(SDL_CFLAGS) -pthread -DMYAGENT_ROOT=\"$(ROOT)\"

# LuaJIT is always linked statically; no system luajit binary is needed at runtime.
STATIC_LIBS := -Wl,-Bstatic -lSDL2_ttf -lSDL2_image -lSDL2 $(LUAJIT_A) -Wl,-Bdynamic

myagent-voice: main.c lua_embed.h $(LIBXDO)
	$(CC) $(CFLAGS) -rdynamic $(RPATH) -o $@ main.c $(STATIC_LIBS) $(SDL_STATIC_DEPS) -lasound -pthread -lm -ldl

# Fallback build when the SDL static archives are unavailable.
dynamic: main.c lua_embed.h $(LIBXDO)
	$(CC) $(CFLAGS) -rdynamic $(RPATH) -o myagent-voice main.c $(LUAJIT_A) $(SDL_LIBS) -lasound -pthread -lm -ldl

lua_embed.h: gen_embed.py ../../tools/winctl.lua ../../tools/xdo.lua ../icon.png
	python3 gen_embed.py -o $@ winctl_lua=../../tools/winctl.lua \
	  xdo_lua=../../tools/xdo.lua icon_png=../icon.png

clean:
	rm -f myagent-voice lua_embed.h

.PHONY: clean dynamic
