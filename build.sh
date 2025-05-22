#!/bin/bash
set -e

export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-

# 配置项
KERNEL_DEFCONFIG=onedots_stm32mp157_pro_defconfig
LOADADDR=0xC2000040

OUTPUT_DIR="../output"
BOOT_DIR="./boot"
BOOTFS_IMG="$OUTPUT_DIR/bootfs.ext4"
BOOTFS_SIZE_MB=32

DTB_DIR="./arch/arm/boot/dts"
BUILD_DIR="./arch/arm/boot"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$BOOT_DIR"
mkdir -p "$(dirname "$BOOTFS_IMG")"  # <--- 确保 bootfs.ext4 所在目录存在

echo "🔧 [1/4] 配置内核：$KERNEL_DEFCONFIG"
make $KERNEL_DEFCONFIG

echo "🚀 [2/4] 编译 uImage 和设备树..."
make uImage LOADADDR=$LOADADDR -j$(nproc)
make dtbs -j$(nproc)

echo "📁 [3/4] 拷贝 uImage 和必要的 dtb 到 boot 目录..."
cp $BUILD_DIR/uImage $BOOT_DIR/
# cp $DTB_DIR/stm32mp157c-100ask-512d-lcd-v1.dtb $BOOT_DIR/
cp $DTB_DIR/stm32mp157c-onedots-512d-v1.dtb $BOOT_DIR/
echo "🧰 [4/4] 创建 bootfs.ext4 镜像（无需 sudo）..."

# 创建空的 FAT 镜像
dd if=/dev/zero of="$BOOTFS_IMG" bs=1M count=$BOOTFS_SIZE_MB
mkfs.vfat "$BOOTFS_IMG"

# 使用 mtools 工具复制文件到镜像
export MTOOLS_SKIP_CHECK=1
for item in "$BOOT_DIR"/*; do
    if [ -d "$item" ]; then
        mmd -i "$BOOTFS_IMG" ::/$(basename "$item")
        mcopy -i "$BOOTFS_IMG" -s "$item"/* ::/$(basename "$item")/
    else
        mcopy -i "$BOOTFS_IMG" "$item" ::/
    fi
done
rm $BOOT_DIR/uImage
echo "✅ bootfs.ext4 已生成于：$BOOTFS_IMG"

