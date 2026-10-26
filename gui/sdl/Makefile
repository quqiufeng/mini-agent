CC ?= gcc
CFLAGS := -O2 -Wall $(shell pkg-config --cflags sdl2 SDL2_ttf) -pthread
LDFLAGS := $(shell pkg-config --libs sdl2 SDL2_ttf) -lasound -pthread

myagent-voice: main.c
	$(CC) $(CFLAGS) -o $@ main.c $(LDFLAGS) -lm

clean:
	rm -f myagent-voice
