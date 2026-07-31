export TARGET = iphone:clang:15.6:15.0
export ARCHS ?= arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = VcamStreamDaemon
VcamStreamDaemon_FILES        = main.m
VcamStreamDaemon_CFLAGS       = -fobjc-arc
VcamStreamDaemon_LDFLAGS      = -lz
VcamStreamDaemon_FRAMEWORKS   = Foundation CoreFoundation
VcamStreamDaemon_CODESIGN_FLAGS = -Sentitlements.plist
VcamStreamDaemon_INSTALL_PATH = /var/jb/usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
