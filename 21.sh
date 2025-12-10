#!/bin/bash

# 一键安装 AnyLink 并配置 systemd 服务

# 检查是否以 root 执行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 用户执行此脚本"
  exit 1
fi

# 定义变量
ANYLINK_DIR="/usr/local/anylink-deploy"
SERVICE_FILE="anylink.service"

# 判断系统类型
if [ -f /etc/centos-release ]; then
    SYSTEMD_DIR="/usr/lib/systemd/system"
elif [ -f /etc/lsb-release ] || [ -f /etc/debian_version ]; then
    SYSTEMD_DIR="/lib/systemd/system"
else
    echo "未识别的操作系统，请手动指定 systemd 目录"
    exit 1
fi

echo "系统检测完成，systemd 目录: $SYSTEMD_DIR"

# 创建目录并复制 anylink-deploy 文件夹
if [ ! -d "$ANYLINK_DIR" ]; then
    echo "创建目录 $ANYLINK_DIR"
    mkdir -p "$ANYLINK_DIR"
fi

echo "请将 anylink-deploy 文件夹放入当前目录下"
read -p "确认已放好 anylink-deploy 文件夹后按回车继续..."

cp -r ./anylink-deploy/* "$ANYLINK_DIR/"

# 添加执行权限
chmod +x "$ANYLINK_DIR/anylink"
echo "执行权限已添加"

# 复制 systemd 服务文件
if [ ! -f "./$SERVICE_FILE" ]; then
    echo "未找到 $SERVICE_FILE，请确保在当前目录下"
    exit 1
fi

cp "./$SERVICE_FILE" "$SYSTEMD_DIR/"
echo "服务文件已复制到 $SYSTEMD_DIR"

# 重新加载 systemd
systemctl daemon-reload

# 启动服务
systemctl start anylink
echo "服务已启动"

# 设置开机自启
systemctl enable anylink
echo "服务已设置为开机自启"

echo "安装和配置完成！可以使用 'systemctl status anylink' 查看状态"
