# ============================================================
# id5hook — 纯 Dylib 内存扫描悬浮窗插件
# 无根/巨魔 (TrollFools) 环境, 无 Substrate / Substitute
# ============================================================

TARGET := iphone:clang:latest:14.0
ARCHS  := arm64

# 无根包格式 (兼容 Dopamine / palera1n / TrollFools)
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

# 使用 library 模板而非 tweak — 不链接 substrate
LIBRARY_NAME = id5hook

id5hook_FILES = Tweak.mm

# ARC 支持 + C++17, 关闭废弃 API 警告（兼容性回退路径需要）
id5hook_CFLAGS  = -fobjc-arc -std=c++17 -Wno-deprecated-declarations -Wno-unused-parameter
id5hook_CCFLAGS = -std=c++17 -Wno-deprecated-declarations -Wno-unused-parameter

# 链接所需框架（无 substrate）
id5hook_LDFLAGS = -framework UIKit -framework Foundation -framework CoreGraphics

include $(THEOS_MAKE_PATH)/library.mk
