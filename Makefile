INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = NCMUnlock

NCMUnlock_FILES = Tweak/Tweak.x Tweak/NCMUnlockAPI.m Tweak/SettingsHelper.m
NCMUnlock_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
NCMUnlock_FRAMEWORKS = UIKit Foundation Security

include $(THEOS_MAKE_PATH)/tweak.mk
