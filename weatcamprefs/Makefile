export TARGET = iphone:clang:15.6:15.0
export ARCHS ?= arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = weatcamprefs

weatcamprefs_FILES    = WeatCamRootListController.m
weatcamprefs_CFLAGS   = -fobjc-arc -Wno-deprecated-declarations
weatcamprefs_FRAMEWORKS = UIKit Preferences AVFoundation PhotosUI UniformTypeIdentifiers
weatcamprefs_PRIVATE_FRAMEWORKS = Preferences MobileCoreServices
weatcamprefs_INSTALL_PATH = /var/jb/Library/PreferenceBundles
weatcamprefs_PRINCIPAL_CLASS = WeatCamRootListController

include $(THEOS_MAKE_PATH)/bundle.mk
