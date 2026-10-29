"""生成网页版 App 用的中文字体子集。

Flutter 网页版默认从 fonts.gstatic.com 下载中文字体，国内无法访问，界面会显示成方块。
这里把思源黑体（Noto Sans SC，SIL OFL 1.1 授权）裁剪成 GB2312 常用汉字 + ASCII + 常用符号，
放到 mobile/web/fonts/ 下，由网页版 App 启动时从网关加载（APK 不包含这些文件）。

用法：
    pip install fonttools
    curl -L -o NotoSansSC.ttf "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf"
    python tools/subset_cjk_font.py NotoSansSC.ttf mobile/web/fonts
"""

import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

WEIGHTS = {"Regular": 400, "Bold": 700}


def charset() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}
    # GB2312 一、二级汉字及全角符号
    for hi in range(0xA1, 0xF8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.add(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    for start, end in [(0xA0, 0xFF), (0x2000, 0x206F), (0x2100, 0x215F), (0x2190, 0x21FF), (0x3000, 0x303F), (0xFF00, 0xFFEF)]:
        chars.update(chr(c) for c in range(start, end + 1))
    return "".join(sorted(chars))


def main(source: str, out_dir: str) -> None:
    text = charset()
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    for style, weight in WEIGHTS.items():
        font = instancer.instantiateVariableFont(TTFont(source), {"wght": weight})
        options = subset.Options()
        options.layout_features = ["*"]
        options.name_IDs = ["*"]
        options.notdef_outline = True
        subsetter = subset.Subsetter(options)
        subsetter.populate(text=text)
        subsetter.subset(font)
        target = out / f"NotoSansSC-{style}.ttf"
        font.save(target)
        print(f"{target}: {target.stat().st_size // 1024} KB, {len(text)} chars")


if __name__ == "__main__":
    main(*sys.argv[1:3])
