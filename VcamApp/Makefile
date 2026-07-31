export TARGET = iphone:clang:15.6:15.0
export ARCHS ?= arm64 arm64e

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VcamApp
VcamApp_FILES              = main.m VcamRootViewController.m VcamAppDelegate.m
VcamApp_FRAMEWORKS         = UIKit CoreGraphics Foundation MobileCoreServices
VcamApp_CFLAGS             = -fobjc-arc -ObjC -Wno-deprecated-declarations
VcamApp_CODESIGN_FLAGS     = -Sentitlements.plist
VcamApp_INSTALL_PATH       = /var/jb/Applications

include $(THEOS_MAKE_PATH)/application.mk
