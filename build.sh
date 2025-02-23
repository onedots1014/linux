#!/bin/bash
set -e

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-

# 配置项
KERNEL_DEFCONFIG=onedots_stm32mp157_pro_defconfig
LOADADDR=0xC2000040

OUTPUT_DIR="../output"
BOOTFS_IMG="$OUTPUT_DIR/bootfs.ext4"
BOOTFS_SIZE_MB=32

# 板级支持文件目录
BOARD_BOOT_DIR="../boards/onedots-stm32mp157/boot"

# 内核构建目录
DTB_DIR="./arch/arm/boot/dts"
BUILD_DIR="./arch/arm/boot"

# 临时目录用于组织bootfs内容
TEMP_BOOTFS_DIR="$OUTPUT_DIR/temp_bootfs"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TEMP_BOOTFS_DIR"

echo "🔧 [1/4] 配置内核：$KERNEL_DEFCONFIG"
make $KERNEL_DEFCONFIG

echo "🚀 [2/4] 编译 uImage 和设备树..."
make uImage LOADADDR=$LOADADDR -j$(nproc)
make dtbs -j$(nproc)

echo "📁 [3/4] 准备 bootfs 内容..."
# 清空临时目录
rm -rf "$TEMP_BOOTFS_DIR"/*

# 拷贝编译生成的文件到临时目录
cp "$BUILD_DIR/uImage" "$TEMP_BOOTFS_DIR/"
cp "$DTB_DIR/stm32mp157c-onedots-512d-v1.dtb" "$TEMP_BOOTFS_DIR/"

# 拷贝板级支持文件到临时目录
if [ -d "$BOARD_BOOT_DIR" ]; then
    for item in "$BOARD_BOOT_DIR"/*; do
        if [ -e "$item" ]; then
            cp -r "$item" "$TEMP_BOOTFS_DIR/"
        fi
    done
    echo "✅ 板级支持文件已拷贝到临时目录"
else
    echo "⚠️  板级支持文件目录不存在：$BOARD_BOOT_DIR"
fi

echo "🧰 [4/4] 创建 bootfs.ext4 镜像..."
# 删除旧的镜像文件
rm -f "$BOOTFS_IMG"

# 创建空的 FAT 镜像
dd if=/dev/zero of="$BOOTFS_IMG" bs=1M count=$BOOTFS_SIZE_MB
mkfs.vfat "$BOOTFS_IMG"

# 使用 mtools 工具复制文件到镜像（无需 sudo）
export MTOOLS_SKIP_CHECK=1
for item in "$TEMP_BOOTFS_DIR"/*; do
    if [ -e "$item" ]; then
        if [ -d "$item" ]; then
            # 创建目录并复制内容
            mmd -i "$BOOTFS_IMG" ::/$(basename "$item")
            mcopy -i "$BOOTFS_IMG" -s "$item"/* ::/$(basename "$item")/
        else
            # 复制文件
            mcopy -i "$BOOTFS_IMG" "$item" ::/
        fi
    fi
done

# 清理临时目录
rm -rf "$TEMP_BOOTFS_DIR"

echo "✅ bootfs.ext4 已生成于：$BOOTFS_IMG"
echo "📦 bootfs 镜像大小：$(du -h "$BOOTFS_IMG" | cut -f1)"

# 显示镜像内容
echo "📋 bootfs 镜像内容："
mdir -i "$BOOTFS_IMG" ::/

