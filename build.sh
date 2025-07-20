#!/bin/bash
set -e

# 脚本配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# 构建配置
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-

# 可配置参数（可通过环境变量覆盖）
KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-onedots_stm32mp157c_defconfig}"
LOADADDR="${LOADADDR:-0xC2000040}"
DEVICE_TREE="${DEVICE_TREE:-stm32mp157c-onedots-512d-v1}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

# 输出配置
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/output}"
BOOTFS_IMG="$OUTPUT_DIR/bootfs.ext4"
BOOTFS_SIZE_MB="${BOOTFS_SIZE_MB:-32}"
BOOTFS_TYPE="${BOOTFS_TYPE:-vfat}"

# 板级支持文件目录
BOARD_NAME="${BOARD_NAME:-onedots-stm32mp157}"
BOARD_BOOT_DIR="$PROJECT_ROOT/boards/stm32mp157/$BOARD_NAME/boot"

# 内核构建目录
DTB_DIR="./arch/arm/boot/dts"
BUILD_DIR="./arch/arm/boot"

# 临时目录
TEMP_BOOTFS_DIR="$OUTPUT_DIR/temp_bootfs"

# 构建选项
CLEAN_BUILD="${CLEAN_BUILD:-false}"
VERBOSE="${VERBOSE:-false}"
SKIP_BOOTFS="${SKIP_BOOTFS:-false}"
BUILD_TYPE="${BUILD_TYPE:-release}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

log_step() {
    echo -e "${CYAN}🔧 $1${NC}"
}

log_build() {
    echo -e "${GREEN}🚀 $1${NC}"
}

# Help function
show_help() {
    cat << EOF
Linux Kernel Build Script

Usage: $0 [options]

Options:
    -h, --help              Show help information
    -c, --clean             Clean before build
    -v, --verbose           Enable verbose output
    -j, --jobs N            Specify parallel build jobs (default: $(nproc))
    -o, --output DIR        Specify output directory (default: ../output)
    -d, --defconfig CFG     Specify defconfig (default: $KERNEL_DEFCONFIG)
    -t, --device-tree DT    Specify device tree name (default: $DEVICE_TREE)
    -b, --board BOARD       Specify board name (default: $BOARD_NAME)
    --skip-bootfs           Skip bootfs image creation
    --bootfs-size N         Specify bootfs image size in MB (default: $BOOTFS_SIZE_MB)
    --bootfs-type TYPE      Specify bootfs filesystem type (default: $BOOTFS_TYPE)
    --loadaddr ADDR         Specify kernel load address (default: $LOADADDR)
    --debug                 Enable debug build

Environment Variables:
    CROSS_COMPILE           Cross-compiler toolchain prefix (default: arm-linux-gnueabi-)
    ARCH                    Target architecture (default: arm)

Examples:
    $0                       # Default build
    $0 -c -j4               # Clean build with 4 parallel jobs
    $0 --skip-bootfs        # Only compile kernel, skip bootfs image
    $0 --debug --verbose    # Debug build with verbose output
    $0 --bootfs-size 64     # Use 64MB bootfs image
EOF
}

# 参数解析
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--clean)
                CLEAN_BUILD=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -j|--jobs)
                BUILD_JOBS="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                BOOTFS_IMG="$OUTPUT_DIR/bootfs.ext4"
                TEMP_BOOTFS_DIR="$OUTPUT_DIR/temp_bootfs"
                shift 2
                ;;
            -d|--defconfig)
                KERNEL_DEFCONFIG="$2"
                shift 2
                ;;
            -t|--device-tree)
                DEVICE_TREE="$2"
                shift 2
                ;;
            -b|--board)
                BOARD_NAME="$2"
                BOARD_BOOT_DIR="$PROJECT_ROOT/boards/stm32mp157/$BOARD_NAME/boot"
                shift 2
                ;;
            --skip-bootfs)
                SKIP_BOOTFS=true
                shift
                ;;
            --bootfs-size)
                BOOTFS_SIZE_MB="$2"
                shift 2
                ;;
            --bootfs-type)
                BOOTFS_TYPE="$2"
                shift 2
                ;;
            --loadaddr)
                LOADADDR="$2"
                shift 2
                ;;
            --debug)
                BUILD_TYPE=debug
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Environment check
check_environment() {
    log_step "[Environment Check] Verifying build environment..."
    
    # Check cross-compiler toolchain
    if ! command -v "${CROSS_COMPILE}gcc" &> /dev/null; then
        log_error "Cross-compiler toolchain not found: ${CROSS_COMPILE}gcc"
        log_info "Please ensure ARM cross-compiler toolchain is installed"
        exit 1
    fi
    
    # Check required tools
    local required_tools=("make" "dd" "mkfs.vfat" "mtools")
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            log_error "Required tool not found: $tool"
            exit 1
        fi
    done
    
    # Check mtools configuration
    if [[ "$SKIP_BOOTFS" != "true" ]]; then
        export MTOOLS_SKIP_CHECK=1
        if ! mdir --version &> /dev/null; then
            log_warning "mtools may have configuration issues, but will try to continue"
        fi
    fi
    
    # Display toolchain information
    local gcc_version=$(${CROSS_COMPILE}gcc --version | head -n1)
    log_info "Cross-compiler toolchain: $gcc_version"
    log_info "Target architecture: $ARCH"
    log_info "Parallel jobs: $BUILD_JOBS"
    log_info "Build type: $BUILD_TYPE"
    log_info "Kernel load address: $LOADADDR"
}

# 清理构建
clean_build() {
    if [[ "$CLEAN_BUILD" == "true" ]]; then
        log_step "[清理] 清理之前的构建产物..."
        make distclean || true
        rm -rf "$OUTPUT_DIR"
        log_success "构建目录已清理"
    fi
}

# Configure kernel
configure_kernel() {
    log_step "[1/4] Configure kernel: $KERNEL_DEFCONFIG"
    
    # Check if defconfig exists
    if [[ ! -f "arch/arm/configs/$KERNEL_DEFCONFIG" ]]; then
        log_error "defconfig file not found: arch/arm/configs/$KERNEL_DEFCONFIG"
        exit 1
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        make $KERNEL_DEFCONFIG
    else
        make $KERNEL_DEFCONFIG > /dev/null 2>&1
    fi
    
    # Enable debug options if debug build
    if [[ "$BUILD_TYPE" == "debug" ]]; then
        log_info "Enabling debug build options..."
        # Add debug-related configuration modifications here
        # scripts/config --enable DEBUG_KERNEL
        # scripts/config --enable DEBUG_INFO
    fi
    
    log_success "Kernel configuration completed: $KERNEL_DEFCONFIG"
}

# Compile kernel and device tree
compile_kernel() {
    log_build "[2/4] Compiling kernel and device tree..."
    
    local start_time=$(date +%s)
    
    # Compile uImage
    log_info "Compiling uImage (LOADADDR=$LOADADDR)..."
    local uimage_cmd="make uImage LOADADDR=$LOADADDR -j$BUILD_JOBS"
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Executing command: $uimage_cmd"
        $uimage_cmd
    else
        $uimage_cmd > /dev/null 2>&1
    fi
    
    # Compile device tree
    log_info "Compiling device tree..."
    local dtbs_cmd="make dtbs -j$BUILD_JOBS"
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Executing command: $dtbs_cmd"
        $dtbs_cmd
    else
        $dtbs_cmd > /dev/null 2>&1
    fi
    
    # Verify build artifacts
    if [[ ! -f "$BUILD_DIR/uImage" ]]; then
        log_error "uImage compilation failed"
        exit 1
    fi
    
    if [[ ! -f "$DTB_DIR/$DEVICE_TREE.dtb" ]]; then
        log_error "Device tree compilation failed: $DEVICE_TREE.dtb"
        exit 1
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log_success "Kernel compilation completed (elapsed: ${duration}s)"
    
    # Display file sizes
    log_info "uImage size: $(du -h "$BUILD_DIR/uImage" | cut -f1)"
    log_info "Device tree size: $(du -h "$DTB_DIR/$DEVICE_TREE.dtb" | cut -f1)"
}

# Prepare bootfs content
prepare_bootfs() {
    if [[ "$SKIP_BOOTFS" == "true" ]]; then
        log_info "[3/4] Skip bootfs preparation (--skip-bootfs)"
        return 0
    fi
    
    log_step "[3/4] Preparing bootfs content..."
    
    # Create output and temporary directories
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$TEMP_BOOTFS_DIR"
    
    # Clear temporary directory
    rm -rf "$TEMP_BOOTFS_DIR"/*
    
    # Copy compiled files
    log_info "Copying kernel image..."
    cp -v "$BUILD_DIR/uImage" "$TEMP_BOOTFS_DIR/"
    
    log_info "Copying device tree..."
    cp -v "$DTB_DIR/$DEVICE_TREE.dtb" "$TEMP_BOOTFS_DIR/"
    
    # Copy board support files
    if [[ -d "$BOARD_BOOT_DIR" ]]; then
        log_info "Copying board support files from: $BOARD_BOOT_DIR"
        local copied_board_files=0
        for item in "$BOARD_BOOT_DIR"/*; do
            if [[ -e "$item" ]]; then
                cp -rv "$item" "$TEMP_BOOTFS_DIR/"
                copied_board_files=$((copied_board_files + 1))
            fi
        done
        log_success "Copied $copied_board_files board support files"
    else
        log_warning "Board support files directory not found: $BOARD_BOOT_DIR"
    fi
    
    # Display temporary directory content
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "bootfs temporary directory content:"
        ls -la "$TEMP_BOOTFS_DIR"
    fi
    
    log_success "bootfs content preparation completed"
}

# 创建 bootfs 镜像
create_bootfs() {
    if [[ "$SKIP_BOOTFS" == "true" ]]; then
        log_info "[4/4] 跳过 bootfs 镜像创建 (--skip-bootfs)"
        return 0
    fi
    
    log_step "[4/4] 创建 bootfs 镜像..."
    
    # 删除旧的镜像文件
    rm -f "$BOOTFS_IMG"
    
    log_info "创建 ${BOOTFS_SIZE_MB}MB 的 $BOOTFS_TYPE 镜像..."
    
    # 创建空镜像
    dd if=/dev/zero of="$BOOTFS_IMG" bs=1M count=$BOOTFS_SIZE_MB 2>/dev/null
    
    # 格式化文件系统
    case "$BOOTFS_TYPE" in
        vfat|fat32)
            mkfs.vfat "$BOOTFS_IMG" > /dev/null 2>&1
            ;;
        ext4)
            mkfs.ext4 -F "$BOOTFS_IMG" > /dev/null 2>&1
            ;;
        *)
            log_error "不支持的文件系统类型: $BOOTFS_TYPE"
            exit 1
            ;;
    esac
    
    # 拷贝文件到镜像
    log_info "拷贝文件到镜像..."
    local copied_items=0
    for item in "$TEMP_BOOTFS_DIR"/*; do
        if [[ -e "$item" ]]; then
            if [[ -d "$item" ]]; then
                # 创建目录并复制内容
                mmd -i "$BOOTFS_IMG" ::/$(basename "$item") 2>/dev/null || true
                mcopy -i "$BOOTFS_IMG" -s "$item"/* ::/$(basename "$item")/ 2>/dev/null || true
            else
                # 复制文件
                mcopy -i "$BOOTFS_IMG" "$item" ::/ 2>/dev/null || true
            fi
            ((copied_items++))
        fi
    done
    
    log_success "已拷贝 $copied_items 个项目到镜像"
    
    # 清理临时目录
    rm -rf "$TEMP_BOOTFS_DIR"
    
    # 显示镜像信息
    local img_size=$(du -h "$BOOTFS_IMG" | cut -f1)
    log_success "bootfs 镜像创建完成: $BOOTFS_IMG ($img_size)"
    
    # 显示镜像内容
    if [[ "$VERBOSE" == "true" ]]; then
        echo
        log_info "📋 bootfs 镜像内容:"
        mdir -i "$BOOTFS_IMG" ::/ 2>/dev/null || true
    fi
}

# 显示构建结果
show_results() {
    log_success "🎉 Linux 内核构建完成！"
    
    echo
    log_info "📦 构建产物:"
    log_info "  uImage: $BUILD_DIR/uImage"
    log_info "  设备树: $DTB_DIR/$DEVICE_TREE.dtb"
    
    if [[ "$SKIP_BOOTFS" != "true" ]]; then
        log_info "  bootfs 镜像: $BOOTFS_IMG"
        if [[ -f "$BOOTFS_IMG" ]]; then
            local bootfs_size=$(du -h "$BOOTFS_IMG" | cut -f1)
            log_info "  bootfs 大小: $bootfs_size"
        fi
    fi
    
    echo
    log_info "💡 提示:"
    log_info "  - 使用 $0 --help 查看更多选项"
    log_info "  - 使用 $0 --clean 进行完全清理构建"
    log_info "  - 使用 $0 --skip-bootfs 仅编译内核"
    log_info "  - 使用 $0 --verbose 查看详细构建过程"
}

# 错误处理
cleanup_on_error() {
    log_error "构建过程中发生错误"
    if [[ -d "$TEMP_BOOTFS_DIR" ]]; then
        log_info "清理临时目录..."
        rm -rf "$TEMP_BOOTFS_DIR"
    fi
    exit 1
}

trap 'cleanup_on_error' ERR

# 主函数
main() {
    # 解析命令行参数
    parse_args "$@"
    
    # 切换到脚本目录
    cd "$SCRIPT_DIR"
    
    # Display build information
    echo
    log_info "🚀 Starting Linux kernel build for STM32MP157"
    log_info "============================================"
    log_info "Kernel config: $KERNEL_DEFCONFIG"
    log_info "Device tree: $DEVICE_TREE"
    log_info "Board name: $BOARD_NAME"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Build jobs: $BUILD_JOBS"
    log_info "Load address: $LOADADDR"
    if [[ "$SKIP_BOOTFS" != "true" ]]; then
        log_info "bootfs size: ${BOOTFS_SIZE_MB}MB ($BOOTFS_TYPE)"
    else
        log_info "bootfs: skip creation"
    fi
    log_info "============================================"
    echo
    
    # 执行构建步骤
    check_environment
    clean_build
    configure_kernel
    compile_kernel
    prepare_bootfs
    create_bootfs
    show_results
}

# 执行主函数
main "$@"
