#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#配置自检：在真正编译之前，把"必然失败"的配置挑出来。
#整场编译要跑两小时以上，而这类问题几十秒就能确认，早失败比晚失败省事得多。
#只做确定性检查，误报会直接拦下编译，所以判定条件尽量保守。

CFG="./.config"
FAILED=0

if [ ! -f "$CFG" ]; then
	echo "skip config check: $CFG not found"
	exit 0
fi

#检查某个包是否被选中
SYM_ON() {
	grep -q "^CONFIG_PACKAGE_$1=y$" "$CFG"
}

#1、QMI WWAN 驱动冲突
#QModem 自带的 kmod-qmi_wwan_f / kmod-qmi_wwan_q 与 feeds 的
#kmod-usb-net-qmi-wwan-fibocom / -quectel 会安装同名的
#lib/modules/<内核版本>/qmi_wwan_f.ko、qmi_wwan_q.ko。
#apk 装包时会报 "trying to overwrite ... owned by ..."，
#package/install 返回 Error 2 导致 world 失败。
QMODEM_VENDOR=""
for S in kmod-qmi_wwan_f kmod-qmi_wwan_q; do
	SYM_ON "$S" && QMODEM_VENDOR="$QMODEM_VENDOR $S"
done
FEEDS_VENDOR=""
for S in kmod-usb-net-qmi-wwan-fibocom kmod-usb-net-qmi-wwan-quectel; do
	SYM_ON "$S" && FEEDS_VENDOR="$FEEDS_VENDOR $S"
done
if [ -n "$QMODEM_VENDOR" ] && [ -n "$FEEDS_VENDOR" ]; then
	echo "ERROR: QMI WWAN 驱动冲突，编译会卡在最后的装包阶段！"
	echo "       QModem 厂商驱动:$QMODEM_VENDOR"
	echo "       feeds 驱动      :$FEEDS_VENDOR"
	echo "       两组包安装同名文件 qmi_wwan_f.ko / qmi_wwan_q.ko，只能留一组。"
	echo "       请修改 Config/GENERAL.txt（默认留 QModem 厂商驱动）。"
	FAILED=1
fi

#2、同名包重复定义
#两个 Makefile 定义同一个包名时，kconfig 会报
#"symbol PACKAGE_xxx is selected by PACKAGE_xxx" 递归依赖，
#并且两份源码会各自编译一遍，最终固件里的版本还可能不是想要的。
OAF_FILES=$(grep -rl --include=Makefile "KernelPackage/oaf" ./package ./feeds 2>/dev/null)
OAF_COUNT=$(printf '%s\n' "$OAF_FILES" | grep -c .)
if [ "$OAF_COUNT" -gt 1 ]; then
	echo "WARNING: 有 $OAF_COUNT 个 Makefile 同时定义 kmod-oaf，会重复编译："
	printf '%s\n' "$OAF_FILES" | sed 's/^/         /'
	echo "         请检查 Scripts/Packages.sh 中 OpenAppFilter 的删除清单。"
fi

if [ "$FAILED" -ne 0 ]; then
	echo "配置自检未通过，已提前终止。"
	exit 1
fi

echo "配置自检通过。"
