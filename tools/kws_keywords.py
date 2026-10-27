#!/usr/bin/env python3
"""生成 sherpa-onnx pinyin KWS 关键词文件。

用法: kws_keywords.py "你好星期五,星期五" [更多词...]
或:   VOICE_WAKE="你好星期五,星期五" kws_keywords.py

模型 sherpa-onnx-kws-zipformer-wenetspeech-3.3M 的建模单元是
“声母 + 带声调韵母”，例如 你好 -> n ǐ h ǎo。
"""
import os
import sys

from pypinyin import lazy_pinyin, Style

INITIALS = ("zh", "ch", "sh", "b", "p", "m", "f", "d", "t", "n", "l",
            "g", "k", "h", "j", "q", "x", "r", "z", "c", "s", "y", "w")


def split_syllable(syllable):
    for ini in INITIALS:
        if syllable.startswith(ini) and len(syllable) > len(ini):
            return [ini, syllable[len(ini):]]
    return [syllable]


def tokens_for(word):
    out = []
    for syllable in lazy_pinyin(word, style=Style.TONE):
        out.extend(split_syllable(syllable))
    return out


def main():
    text = " ".join(sys.argv[1:]) or os.environ.get("VOICE_WAKE", "你好星期五,星期五")
    words = [w.strip() for w in text.replace("，", ",").split(",") if w.strip()]
    seen = set()
    for word in words:
        if word in seen:
            continue
        seen.add(word)
        print(" ".join(tokens_for(word)) + " @" + word)


if __name__ == "__main__":
    main()
