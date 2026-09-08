TARGET := iphone:clang:latest:16.0

ARCHS := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := SearchGlass

SearchGlass_FILES := Tweak.xm

SearchGlass_CFLAGS := -fobjc-arc

SearchGlass_FRAMEWORKS := UIKit

SearchGlass_PRIVATE_FRAMEWORKS := Preferences

SearchGlass_EXTRA_FILES += \
    Resources/AboutIcon.png:/Library/Application Support/SearchGlass/AboutIcon.png \
    Resources/SoftwareUpdateIcon.png:/Library/Application Support/SearchGlass/SoftwareUpdateIcon.png

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Preferences"
