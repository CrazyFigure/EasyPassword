# -*- coding: utf-8 -*-
"""EasyPassword 图标生成流水线（Windows + Android 统一入口）

设计要点
--------
1. 唯一数据源：项目根目录 `logo.png`（白底 + 蓝钥匙盾牌）。
2. 缩放口径按"钥匙高度占画布的比例"表述，两个旋钮：
   - `DEFAULT_CONTENT_RATIO`（默认 0.533）：图块类图标，即 Windows ICO + Android 传统图标。
   - `DEFAULT_ADAPTIVE_CONTENT_RATIO`（默认 0.533）：Android 自适应图标前景。
   两者当前取值相同，但刻意分开：自适应图标的可见大小受 72dp 安全区规则约束，已经确认观感合适，
   不应随着"图块类图标"后续微调而被一起带大或带小。
3. Windows 小尺寸帧例外：`WINDOWS_FRAME_RATIO_OVERRIDES` 把 16/24px 放宽到 0.60（光学尺寸分级）。
   因此同一个 .ico 内不同帧可能来自不同口径，由 `save_windows_ico` 分口径渲染后合并目录结构。
4. 之所以按占比而非"内边距"表述：早期 Windows 用 8%、Android 用 6% 两套 padding 常量，
   分别对应钥匙占 86.2% / 89.3%，跨端难以对齐且极易漂移；改成占比后各端只看一个数。
5. 产出的二进制图标必须提交到仓库：CI（.github/workflows/release.yml）只负责打包，不重新生成图标。

产出清单
--------
- windows/runner/resources/app_icon.ico   EXE 图标（任务栏/任务管理器/资源管理器/Alt-Tab/快捷方式）
- installers/installer.ico                NSIS 安装器与卸载器图标（MUI_ICON/MUI_UNICON）
- android/.../mipmap-{mdpi..xxxhdpi}/ic_launcher.png             传统图标（API < 26）
- android/.../mipmap-{mdpi..xxxhdpi}/ic_launcher_foreground.png  自适应图标前景（API >= 26）
- android/.../drawable/ic_launcher_background.xml                自适应图标背景（纯白）
- android/.../mipmap-anydpi-v26/ic_launcher.xml                  自适应图标配置
- build/icon_preview.png / shell_preview.png / android_icon_preview.png   人工核查用预览

用法
----
    python scripts/make_icons.py                     # 按默认口径重新生成全部图标
    python scripts/make_icons.py --ratio 0.6         # 临时试算：图块类图标钥匙占 60%
    python scripts/make_icons.py --adaptive-ratio 0.5 --only android   # 单独试算自适应前景
    python scripts/make_icons.py --out-root D:/tmp   # 输出到临时目录做方案对比，不动仓库文件
    python scripts/make_icons.py --only windows      # 只生成 Windows 侧
"""

from __future__ import annotations

import argparse
import shutil
import struct
import sys
import tempfile
from pathlib import Path

from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SRC = PROJECT_ROOT / "logo.png"

# 图块类图标（Windows ICO、Android 传统图标）的缩放口径：钥匙高度占画布的比例
DEFAULT_CONTENT_RATIO = 0.533

# Android 自适应图标前景的缩放口径：钥匙高度占 108dp 画布的比例。
# 0.533 等价于"填满中心 72dp 安全区的 80%"，该观感已确认合适，故与图块类图标分开锁定。
DEFAULT_ADAPTIVE_CONTENT_RATIO = 0.533

# 白底透明化阈值。略低于 255，把 JPEG/PNG 压缩产生的近白噪点一并清掉，
# 同时保留钥匙边缘的抗锯齿过渡像素，避免出现白色描边。
WHITE_THRESHOLD = 240

# Windows .ico 内嵌分辨率：覆盖 16(任务栏小图标)/24(任务栏)/32(桌面快捷方式)/
# 48(大图标)/64/128/256(任务管理器详情、Alt-Tab 大图)
WINDOWS_SIZES = (16, 24, 32, 48, 64, 128, 256)

# 小尺寸帧的光学放宽：16/24px 是任务栏最小的两个档位，按统一口径缩到该尺寸后
# 钥匙只剩 8/13px，盾牌与锁孔糊成一团。图标设计的通行做法是给小尺寸单独放大图形
# （光学尺寸分级），此处把这两帧放宽到 0.60，32px 及以上仍用统一口径。
WINDOWS_FRAME_RATIO_OVERRIDES = {16: 0.60, 24: 0.60}

# Android 传统图标尺寸（各 density）
ANDROID_TRADITIONAL_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Android 自适应图标前景画布尺寸（108dp × 各 density）
ANDROID_ADAPTIVE_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}

# 自适应图标安全区占比：中心 72dp / 全画布 108dp。
# 启动器只保证该区域不被遮罩裁掉，因此前景内容必须落在安全区内。
ANDROID_SAFE_RATIO = 72 / 108

# 自适应图标背景色：纯白。浅色启动器上不突兀，深色启动器上蓝色 logo 对比度最佳。
ANDROID_BG_COLOR = "#FFFFFF"


def alpha_bbox(img: Image.Image) -> tuple[int, int, int, int]:
    """按 alpha 通道求内容包围盒。

    显式只取 alpha，避免依赖 Pillow getbbox() 对 RGBA 各通道的判定差异
    （透明像素的 RGB 仍是 255,255,255，按"任一通道非零"会被误判为内容）。
    """
    bbox = img.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError("图像全部为透明，无有效内容，请检查 logo.png 或 WHITE_THRESHOLD")
    return bbox


def white_to_transparent(img: Image.Image) -> Image.Image:
    """把接近纯白的像素置为全透明，保留半透明边缘。

    逐像素处理，量级为 1254×1254 ≈ 157 万次，单次运行约数秒，可接受。
    """
    rgba = img.convert("RGBA")
    pixels = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, _a = pixels[x, y]
            if r >= WHITE_THRESHOLD and g >= WHITE_THRESHOLD and b >= WHITE_THRESHOLD:
                pixels[x, y] = (255, 255, 255, 0)
    return rgba


def load_content() -> tuple[Image.Image, tuple[int, int]]:
    """读取源图 → 白底透明化 → 裁到内容包围盒，返回内容原图与源图尺寸

    逐像素白底透明化是全流程最耗时的一步，因此与"套画布"拆开：
    同一进程内试算多个占比时，内容原图只会被处理一次。
    """
    raw = Image.open(SRC)
    rgba = white_to_transparent(raw)
    return rgba.crop(alpha_bbox(rgba)), raw.size


def to_canvas(content: Image.Image, content_ratio: float) -> Image.Image:
    """内容居中放入正方形画布，使内容最大边占画布 content_ratio。

    画布边长由内容的高宽较大者反推（本 logo 为竖向钥匙，故由高度决定），
    这样"钥匙高度占画布比例"就是精确可控的常量，不随源图尺寸漂移。
    """
    cw, ch = content.size
    side = int(round(max(cw, ch) / content_ratio))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(content, ((side - cw) // 2, (side - ch) // 2))
    return canvas


def read_ico_frames(path: Path) -> list[tuple[bytes, bytes]]:
    """解析 ICO，返回 [(16 字节目录项, 帧数据), ...]

    ICO 结构：6 字节文件头 + N×16 字节目录项 + 各帧数据。
    目录项内 dwBytesInRes(偏移 8) 为帧数据长度，dwImageOffset(偏移 12) 为帧数据起始偏移。
    """
    data = path.read_bytes()
    _reserved, _type, count = struct.unpack_from("<HHH", data, 0)
    if count == 0:
        raise ValueError(f"{path} 中没有任何帧")
    frames = []
    for i in range(count):
        entry = data[6 + i * 16: 6 + (i + 1) * 16]
        length, offset = struct.unpack_from("<II", entry, 8)
        frames.append((entry, data[offset:offset + length]))
    return frames


def merge_ico_files(sources: list[Path], dest: Path) -> None:
    """把多个 ICO 合并为一个，按尺寸升序重排目录项并重算帧偏移

    各帧的编码（≤64 用 32-bit BGRA、256 用 PNG-in-ICO）仍由 Pillow 负责，
    这里只重排容器结构，避免手工构造 BMP 帧带来的兼容风险。
    """
    frames: list[tuple[bytes, bytes]] = []
    for p in sources:
        frames += read_ico_frames(p)
    # 目录项首字节为宽度（256 记作 0），借它排序，保证目录按尺寸升序
    frames.sort(key=lambda f: f[0][0] or 256)

    offset = 6 + 16 * len(frames)
    dir_entries = bytearray()
    payloads = bytearray()
    for entry, payload in frames:
        patched = bytearray(entry)
        struct.pack_into("<I", patched, 8, len(payload))
        struct.pack_into("<I", patched, 12, offset)
        dir_entries += patched
        payloads += payload
        offset += len(payload)

    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(struct.pack("<HHH", 0, 1, len(frames)) + bytes(dir_entries) + bytes(payloads))


def save_windows_ico(content: Image.Image, dest: Path, base_ratio: float, log=None) -> None:
    """打包多分辨率 ICO：按"同一口径的帧"分组，各自渲染后合并

    16/24 帧按 WINDOWS_FRAME_RATIO_OVERRIDES 放宽，其余帧用 base_ratio，
    因此需要分组生成再合并——Pillow 的 ICO 写入器只能对单一源图做缩放。
    """
    groups: dict[float, list[int]] = {}
    for s in WINDOWS_SIZES:
        groups.setdefault(WINDOWS_FRAME_RATIO_OVERRIDES.get(s, base_ratio), []).append(s)

    with tempfile.TemporaryDirectory() as tmp:
        parts = []
        for ratio, sizes in sorted(groups.items()):
            part = Path(tmp) / f"part_{ratio}.ico"
            to_canvas(content, ratio).save(part, format="ICO", sizes=[(s, s) for s in sizes])
            parts.append(part)
            if log:
                log(f"      口径 {ratio} → 帧 {sorted(sizes)}")
        merge_ico_files(parts, dest)


def make_windows(content: Image.Image, out_root: Path, log, base_ratio: float) -> list[Path]:
    """生成 Windows 应用图标，并同步一份给 NSIS 安装器使用（两者必须字节一致）"""
    app_ico = out_root / "windows" / "runner" / "resources" / "app_icon.ico"
    installer_ico = out_root / "installers" / "installer.ico"
    save_windows_ico(content, app_ico, base_ratio, log)
    installer_ico.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(app_ico, installer_ico)
    log(f"  app_icon.ico      {app_ico.stat().st_size} 字节（{len(WINDOWS_SIZES)} 帧）")
    log(f"  installer.ico     {installer_ico.stat().st_size} 字节（同 app_icon.ico 副本）")
    return [app_ico, installer_ico]


def make_android_traditional(master: Image.Image, res_dir: Path, log) -> list[Path]:
    """生成传统 PNG 图标（透明背景）：API < 26 的启动器直接使用"""
    outs = []
    for density, size in ANDROID_TRADITIONAL_SIZES.items():
        dest = res_dir / f"mipmap-{density}" / "ic_launcher.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        master.resize((size, size), Image.Resampling.LANCZOS).save(dest, format="PNG")
        outs.append(dest)
        log(f"  mipmap-{density}/ic_launcher.png  {size}x{size}")
    return outs


def make_android_adaptive(master: Image.Image, res_dir: Path, log) -> list[Path]:
    """生成自适应图标（API >= 26）：背景纯白，前景即主图整体缩到 108dp 画布

    master 由 ADAPTIVE_CONTENT_RATIO 口径构建，本身已留足边距，直接缩到整块画布即可；
    若再套一层安全区缩放会出现"双重留白"，钥匙明显小于 Windows / 传统图标。
    合法性由调用方校验：占比必须 ≤ 安全区 66.7%，否则内容会被启动器遮罩切角。
    """
    outs = []
    for density, full_size in ANDROID_ADAPTIVE_SIZES.items():
        canvas = master.resize((full_size, full_size), Image.Resampling.LANCZOS)
        dest = res_dir / f"mipmap-{density}" / "ic_launcher_foreground.png"
        dest.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(dest, format="PNG")
        outs.append(dest)
        log(f"  mipmap-{density}/ic_launcher_foreground.png  {full_size}x{full_size}")

    # 背景色与自适应配置。内容固定，重复生成结果一致，保持幂等。
    bg_xml = res_dir / "drawable" / "ic_launcher_background.xml"
    bg_xml.parent.mkdir(parents=True, exist_ok=True)
    bg_xml.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- 自适应图标背景：白色 -->\n"
        '<color xmlns:android="http://schemas.android.com/apk/res/android"\n'
        f'    android:color="{ANDROID_BG_COLOR}" />\n',
        encoding="utf-8",
    )
    outs.append(bg_xml)

    anydpi_xml = res_dir / "mipmap-anydpi-v26" / "ic_launcher.xml"
    anydpi_xml.parent.mkdir(parents=True, exist_ok=True)
    anydpi_xml.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- 自适应图标（Android 8.0+）：系统根据启动器自动裁剪形状 -->\n"
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )
    outs.append(anydpi_xml)
    log(f"  drawable/ic_launcher_background.xml  color={ANDROID_BG_COLOR}")
    log("  mipmap-anydpi-v26/ic_launcher.xml")
    return outs


def paste_row(
    sheet: Image.Image,
    items: list[tuple[Image.Image, int]],
    y: int,
    bg: tuple,
    pad: int = 14,
) -> int:
    """在预览图上横向铺一行图标，返回该行右下沿 y 坐标

    items 为 [(主图, 目标尺寸)]：Windows 各帧口径可能不同，因此逐帧给主图，
    不能像早期那样共用一个 master，否则预览会与落盘的 .ico 不一致。
    """
    x = pad
    for master, size in items:
        icon = master.resize((size, size), Image.Resampling.LANCZOS)
        # 先铺底再贴图：透明图标在浅/深底上都能看出实际观感
        cell = Image.new("RGBA", (size, size), bg)
        cell.paste(icon, (0, 0), icon)
        sheet.paste(cell, (x, y), cell)
        x += size + pad
    return y + max(s for _, s in items) + pad


def windows_master(content: Image.Image, size: int, base_ratio: float) -> Image.Image:
    """取某个 Windows 帧尺寸对应的主图：小尺寸帧走放宽口径，其余走统一口径"""
    return to_canvas(content, WINDOWS_FRAME_RATIO_OVERRIDES.get(size, base_ratio))


def make_previews(
    content: Image.Image,
    adaptive_master: Image.Image,
    out_root: Path,
    log,
    base_ratio: float,
) -> list[Path]:
    """生成人工核查预览：Windows 各尺寸、Android 传统/自适应、浅深底任务栏观感

    全部预览实时按落盘口径构建：Windows 逐帧取 windows_master（含 16/24 放宽），
    自适应用 adaptive_master，避免预览与产物不一致。
    """
    build_dir = out_root / "build"
    build_dir.mkdir(parents=True, exist_ok=True)
    outs = []

    # Windows：各尺寸置于浅灰底（近资源管理器/桌面观感）
    light = (245, 245, 245, 255)
    dark = (32, 33, 36, 255)
    pad = 14
    win_w = sum(WINDOWS_SIZES) + pad * (len(WINDOWS_SIZES) + 1)
    win_h = max(WINDOWS_SIZES) + pad * 2
    win_sheet = Image.new("RGBA", (win_w, win_h), (255, 255, 255, 255))
    paste_row(win_sheet, [(windows_master(content, s, base_ratio), s) for s in WINDOWS_SIZES],
              pad, light, pad)
    dest = build_dir / "icon_preview.png"
    win_sheet.save(dest)
    outs.append(dest)
    log("  build/icon_preview.png")

    # Windows 小尺寸浅/深底对照：任务栏可能是深色，需确认 16/24/32 仍清晰
    shell_sizes = (16, 24, 32, 48)
    shell_items = [(windows_master(content, s, base_ratio), s) for s in shell_sizes]
    shell_pad = 16
    shell_w = sum(shell_sizes) + shell_pad * (len(shell_sizes) + 1)
    shell_h = (max(shell_sizes) + shell_pad) * 2 + shell_pad
    shell_sheet = Image.new("RGBA", (shell_w, shell_h), (255, 255, 255, 255))
    y = paste_row(shell_sheet, shell_items, shell_pad, light, shell_pad)
    paste_row(shell_sheet, shell_items, y, dark, shell_pad)
    dest = build_dir / "shell_preview.png"
    shell_sheet.save(dest)
    outs.append(dest)
    log("  build/shell_preview.png")

    # Android：传统图标一行（图块类主图） + 自适应图标用自适应主图，否则两者口径会被混用
    adaptive_size = 192
    fg = adaptive_master.resize((adaptive_size, adaptive_size), Image.Resampling.LANCZOS)
    adaptive = Image.new("RGBA", (adaptive_size, adaptive_size), (255, 255, 255, 255))
    adaptive.paste(fg, (0, 0), fg)

    from PIL import ImageDraw

    def masked(mask_img: Image.Image) -> Image.Image:
        out = Image.new("RGBA", (adaptive_size, adaptive_size), (0, 0, 0, 0))
        out.paste(adaptive, (0, 0), mask_img)
        return out

    circle_mask = Image.new("L", (adaptive_size, adaptive_size), 0)
    ImageDraw.Draw(circle_mask).ellipse([0, 0, adaptive_size - 1, adaptive_size - 1], fill=255)
    rounded_mask = Image.new("L", (adaptive_size, adaptive_size), 0)
    ImageDraw.Draw(rounded_mask).rounded_rectangle(
        [0, 0, adaptive_size - 1, adaptive_size - 1], radius=adaptive_size // 4, fill=255
    )

    trad_sizes = list(ANDROID_TRADITIONAL_SIZES.values())
    trad_master = to_canvas(content, base_ratio)
    trad_w = sum(trad_sizes) + pad * (len(trad_sizes) + 1)
    adaptive_w = adaptive_size * 3 + pad * 4
    sheet_w = max(trad_w, adaptive_w) + pad * 2
    rows_h = (max(trad_sizes) + pad * 2) + (adaptive_size + pad)
    sheet = Image.new("RGBA", (sheet_w, rows_h + pad * 3), (255, 255, 255, 255))
    paste_row(sheet, [(trad_master, s) for s in trad_sizes], pad, light, pad)
    y2 = pad + max(trad_sizes) + pad * 2
    x = pad * 2
    for layer in (adaptive, masked(circle_mask), masked(rounded_mask)):
        cell = layer  # 自适应图标自带白底，无需再铺底
        sheet.paste(cell, (x, y2), cell)
        x += adaptive_size + pad
    dest = build_dir / "android_icon_preview.png"
    sheet.save(dest)
    outs.append(dest)
    log("  build/android_icon_preview.png")
    return outs


def main() -> int:
    parser = argparse.ArgumentParser(description="生成 EasyPassword 各端图标")
    parser.add_argument(
        "--ratio",
        type=float,
        default=DEFAULT_CONTENT_RATIO,
        help="图块类图标（Windows / Android 传统）的钥匙高度占比。默认 0.533",
    )
    parser.add_argument(
        "--adaptive-ratio",
        type=float,
        default=DEFAULT_ADAPTIVE_CONTENT_RATIO,
        help="Android 自适应前景的钥匙高度占比。默认 0.533（= 72dp 安全区的 80%%）",
    )
    parser.add_argument(
        "--out-root",
        type=Path,
        default=PROJECT_ROOT,
        help="输出根目录，默认项目根目录；指向临时目录可做方案对比而不动仓库文件",
    )
    parser.add_argument(
        "--only",
        choices=("all", "windows", "android"),
        default="all",
        help="只生成某一端",
    )
    parser.add_argument("--no-preview", action="store_true", help="不生成预览图")
    args = parser.parse_args()

    # 自适应图标的前景内容必须落在中心 72dp 安全区内，否则会被启动器遮罩切掉四角
    if args.only in ("all", "android") and args.adaptive_ratio > ANDROID_SAFE_RATIO:
        print(
            f"参数错误：--adaptive-ratio {args.adaptive_ratio} 超过自适应图标安全区 "
            f"{ANDROID_SAFE_RATIO:.3f}（108dp 画布中心 72dp），Android 图标四角会被裁掉",
            file=sys.stderr,
        )
        return 2

    out_root: Path = args.out_root.resolve()
    logs: list[str] = []

    def log(msg: str) -> None:
        print(msg)
        logs.append(msg)

    log(f"[1/4] 读取源图: {SRC}")
    if not SRC.exists():
        print(f"源图不存在: {SRC}", file=sys.stderr)
        return 1
    content, source_size = load_content()
    master = to_canvas(content, args.ratio)
    log(f"      源图 {source_size[0]}x{source_size[1]}，"
        f"钥匙内容 {content.size[0]}x{content.size[1]}")
    log(f"      图块类口径 {args.ratio} → 主图 {master.size[0]}x{master.size[1]}，"
        f"钥匙高度占画布 {args.ratio * 100:.1f}%")
    if args.only in ("all", "windows") and WINDOWS_FRAME_RATIO_OVERRIDES:
        overrides = "、".join(f"{s}px→{r}" for s, r in sorted(WINDOWS_FRAME_RATIO_OVERRIDES.items()))
        log(f"      小尺寸帧光学放宽：{overrides}")

    # 自适应主图：口径与图块类相同时直接复用，避免重复套画布
    adaptive_master = master
    if args.only in ("all", "android") and args.adaptive_ratio != args.ratio:
        adaptive_master = to_canvas(content, args.adaptive_ratio)
        log(f"      自适应口径 {args.adaptive_ratio} → 前景 {adaptive_master.size[0]}x"
            f"{adaptive_master.size[1]}，钥匙高度占画布 {args.adaptive_ratio * 100:.1f}%")

    produced: list[Path] = []

    if args.only in ("all", "windows"):
        log("[2/4] Windows 图标")
        produced += make_windows(content, out_root, log, args.ratio)
    if args.only in ("all", "android"):
        log("[3/4] Android 图标")
        res_dir = out_root / "android" / "app" / "src" / "main" / "res"
        produced += make_android_traditional(master, res_dir, log)
        produced += make_android_adaptive(adaptive_master, res_dir, log)

    if not args.no_preview:
        log("[4/4] 预览图")
        produced += make_previews(content, adaptive_master, out_root, log, args.ratio)

    # 自检：实测落盘图标的占比。抗锯齿边缘会算进 bbox，alpha>0 口径通常虚高 1-3pp，
    # 因此同时打印 alpha>64 的"可见内容"占比作为准绳。
    print("\n[自检] 已落盘图标的钥匙高度占比（alpha>0 含淡边 / alpha>64 可见内容）")

    def check(name: str, path: Path, target: float, size: int | None = None) -> None:
        """打印单个图标的实测占比；size 用于从多帧容器（ICO）中挑帧"""
        if not path.exists():
            return
        img = Image.open(path)
        if size:
            img.size = (size, size)
        img = img.convert("RGBA")
        box_all = alpha_bbox(img)
        visible = img.getchannel("A").point(lambda v: 255 if v > 64 else 0).getbbox()
        side = img.size[1]
        h_all = (box_all[3] - box_all[1]) / side * 100
        h_vis = ((visible[3] - visible[1]) / side * 100) if visible else 0.0
        print(f"  {name:34s} {h_all:5.1f}% / {h_vis:5.1f}%（目标 {target * 100:.1f}%）")

    if args.only in ("all", "windows"):
        ico = out_root / "windows" / "runner" / "resources" / "app_icon.ico"
        for s in WINDOWS_SIZES:
            check(f"app_icon.ico@{s}", ico,
                  WINDOWS_FRAME_RATIO_OVERRIDES.get(s, args.ratio), s)
    if args.only in ("all", "android"):
        res_dir = out_root / "android" / "app" / "src" / "main" / "res"
        check("ic_launcher.png@192", res_dir / "mipmap-xxxhdpi/ic_launcher.png", args.ratio)
        check("ic_launcher_foreground.png@432",
              res_dir / "mipmap-xxxhdpi/ic_launcher_foreground.png", args.adaptive_ratio)

    print("\n[完成] 图标已生成")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
