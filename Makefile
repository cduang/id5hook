# ============================================================
# id5hook — 纯 Dylib 内存扫描悬浮窗插件
# 无根/巨魔 (TrollFools) 环境, 无 Substrate / Substitute
# ============================================================

TARGET := iphone:clang:latest:14.0
ARCHS  := arm64

# 目标注入进程 (替换为你目标游戏的进程名 / Bundle ID)
INSTALL_TARGET_PROCESSES = com.example.targetgame

# 无根包格式 (兼容 Dopamine / palera1n / TrollFools)
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = id5hook

id5hook_FILES = Tweak.mm

# ARC 支持 + C++17
id5hook_CFLAGS  = -fobjc-arc -std=c++17
id5hook_CCFLAGS = -std=c++17

# 链接所需框架
id5hook_LDFLAGS = -framework UIKit -framework Foundation -framework CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

# 编译后签名 (无根环境通常用 ldid2)
after-install::
	install.exec "ldid2 -S $(THEOS_STAGING_DIR)/Applications/$(TWEAK_NAME).dylib || true"
