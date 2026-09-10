TARGET := iphone:clang:latest:16.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := SearchGlass

SearchGlass_FILES := Tweak.xm \
    $(wildcard Shared/*.m) \
    $(wildcard Shared/*.x)

SearchGlass_CFLAGS := -fobjc-arc
SearchGlass_FRAMEWORKS := UIKit QuartzCore CoreGraphics CoreText CoreMotion
SearchGlass_PRIVATE_FRAMEWORKS := Preferences

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Preferences"
