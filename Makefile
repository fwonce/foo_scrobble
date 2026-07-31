# foo_scrobble macOS - Pure Makefile build (no Xcode required)
# Usage: make [-j N]

SHELL := /bin/bash
CXX := clang++
CC := clang
AR := ar

FOOBAR2000_TARGET_VERSION := 81

SDK_ROOT := sdk
FB2K_DIR := $(SDK_ROOT)/foobar2000
SRC_DIR := src/foo_scrobble
BUILD_DIR := build

# ===================
# Source files
# ===================

PFC_SRCS := $(wildcard $(SDK_ROOT)/pfc/*.cpp) $(wildcard $(SDK_ROOT)/pfc/*.mm)
FB2K_SDK_SRCS := $(wildcard $(FB2K_DIR)/SDK/*.cpp) $(wildcard $(FB2K_DIR)/SDK/*.mm)
FB2K_HELPERS_SRCS := $(filter-out \
    $(FB2K_DIR)/helpers/DarkMode.cpp \
    $(FB2K_DIR)/helpers/AutoComplete.cpp \
    $(FB2K_DIR)/helpers/CTableEditHelper-Legacy.cpp \
    $(FB2K_DIR)/helpers/dialog_resize_helper.cpp \
    $(FB2K_DIR)/helpers/dropdown_helper.cpp \
    $(FB2K_DIR)/helpers/inplace_edit.cpp \
    $(FB2K_DIR)/helpers/ui_element_helpers.cpp \
    $(FB2K_DIR)/helpers/WindowPositionUtils.cpp \
    $(FB2K_DIR)/helpers/win32_dialog.cpp \
    $(FB2K_DIR)/helpers/win32_misc.cpp \
    $(FB2K_DIR)/helpers/file_win32_wrapper.cpp \
    $(FB2K_DIR)/helpers/ThreadUtils.cpp \
    $(FB2K_DIR)/helpers/image_load_save.cpp \
    $(FB2K_DIR)/helpers/album_art_helpers.cpp \
    ,$(wildcard $(FB2K_DIR)/helpers/*.cpp))
FB2K_MAC_HELPERS_SRCS := $(wildcard $(FB2K_DIR)/helpers-mac/*.m) $(wildcard $(FB2K_DIR)/helpers-mac/*.mm)
SHARED_SRCS := $(FB2K_DIR)/shared/shared-nix.cpp $(FB2K_DIR)/shared/shared-apple.mm $(FB2K_DIR)/shared/audio_math.cpp $(FB2K_DIR)/shared/utf8.cpp
CLIENT_SRCS := $(FB2K_DIR)/foobar2000_component_client/component_client.cpp

PLUGIN_SRCS := \
    $(SRC_DIR)/Main.cpp \
    $(SRC_DIR)/Keys.cpp \
    $(SRC_DIR)/Authorizer.mm \
    $(SRC_DIR)/WebService.mm \
    $(SRC_DIR)/PlaybackScrobbler.cpp \
    $(SRC_DIR)/LastfmScrobbleService.cpp \
    $(SRC_DIR)/ScrobbleService.cpp \
    $(SRC_DIR)/ScrobbleConfig.cpp \
    $(SRC_DIR)/ScrobbleCache.mm \
    $(SRC_DIR)/Mac/fooScrobblePreferences.mm

# ===================
# Object file mapping: src/foo/bar.cpp -> build/objs/foo_bar.o
# ===================

src_to_obj = $(BUILD_DIR)/objs/$(subst /,_,$(patsubst $(SDK_ROOT)/%,sdk_%,$(patsubst $(SRC_DIR)/%,src_%,$(1)))).o

PFC_OBJS := $(foreach s,$(PFC_SRCS),$(call src_to_obj,$s))
SDK_OBJS := $(foreach s,$(FB2K_SDK_SRCS),$(call src_to_obj,$s))
HELPERS_OBJS := $(foreach s,$(FB2K_HELPERS_SRCS),$(call src_to_obj,$s))
MAC_HELPERS_OBJS := $(foreach s,$(FB2K_MAC_HELPERS_SRCS),$(call src_to_obj,$s))
SHARED_OBJS := $(foreach s,$(SHARED_SRCS),$(call src_to_obj,$s))
CLIENT_OBJS := $(foreach s,$(CLIENT_SRCS),$(call src_to_obj,$s))
PLUGIN_OBJS := $(foreach s,$(PLUGIN_SRCS),$(call src_to_obj,$s))

# ===================
# Compiler flags
# ===================

INCLUDES := -I$(FB2K_DIR) -I$(SDK_ROOT) -I$(SRC_DIR)
COMMON_FLAGS := -DFOOBAR2000_TARGET_VERSION=$(FOOBAR2000_TARGET_VERSION) \
    -DNDEBUG -fobjc-arc \
    -Wall -Wno-unused-function -Wno-overloaded-virtual -Wno-reorder-ctor \
    $(INCLUDES)

# Local API keys
LOCAL_KEYS := $(SRC_DIR)/Keys.local.h
ifneq ($(wildcard $(LOCAL_KEYS)),)
LOCAL_KEYS_FLAG := -DFOO_SCROBBLE_HAVE_LOCAL_KEYS
else
LOCAL_KEYS_FLAG :=
endif

CXXFLAGS := -std=c++20 $(COMMON_FLAGS) $(LOCAL_KEYS_FLAG)
OBJCFLAGS := $(COMMON_FLAGS) $(LOCAL_KEYS_FLAG)

FRAMEWORKS := -framework Cocoa

# ===================
# Output
# ===================

COMPONENT_DIR := $(BUILD_DIR)/foo_scrobble.component
COMPONENT_BIN := $(COMPONENT_DIR)/Contents/MacOS/foo_scrobble

LIB_PFC := $(BUILD_DIR)/libpfc-Mac.a
LIB_SDK := $(BUILD_DIR)/libfoobar2000_SDK.a
LIB_HELPERS := $(BUILD_DIR)/libfoobar2000_SDK_helpers.a
LIB_SHARED := $(BUILD_DIR)/libshared.a
LIB_CLIENT := $(BUILD_DIR)/libfoobar2000_component_client.a
LIB_MAC_HELPERS := $(BUILD_DIR)/libhelpers-mac.a

ALL_LIBS := $(LIB_CLIENT) $(LIB_SDK) $(LIB_HELPERS) $(LIB_PFC) $(LIB_SHARED) $(LIB_MAC_HELPERS)

# ===================
# Targets
# ===================

.PHONY: all clean

all: $(COMPONENT_BIN)
	@echo "✓ Built foo_scrobble.component"

$(COMPONENT_BIN): $(ALL_LIBS) $(PLUGIN_OBJS)
	@mkdir -p $(COMPONENT_DIR)/Contents/MacOS $(COMPONENT_DIR)/Contents/Resources
	$(CXX) $(COMMON_FLAGS) -dynamiclib \
		$(PLUGIN_OBJS) $(ALL_LIBS) $(FRAMEWORKS) \
		-o $@
	$(SRC_DIR)/mkplist.sh > $(COMPONENT_DIR)/Contents/Info.plist
	@cp $(SRC_DIR)/Mac/*.xib $(COMPONENT_DIR)/Contents/Resources/ 2>/dev/null || true

# ===================
# Static libraries
# ===================

$(LIB_PFC): $(PFC_OBJS)
	@mkdir -p $(dir $@); $(AR) rcs $@ $^

$(LIB_SDK): $(SDK_OBJS)
	@mkdir -p $(dir $@); $(AR) rcs $@ $^

$(LIB_HELPERS): $(HELPERS_OBJS)
	@mkdir -p $(dir $@); $(AR) rcs $@ $^

$(LIB_MAC_HELPERS): $(MAC_HELPERS_OBJS)
	@mkdir -p $(dir $@); $(AR) rcs $@ $^

$(LIB_SHARED): $(SHARED_OBJS)
	@mkdir -p $(dir $@); $(AR) rcs $@ $^

$(LIB_CLIENT): $(CLIENT_OBJS)
	@mkdir -p $(dir $@); $(AR) rcs $@ $^

# ===================
# Compilation rules
# ===================

# For each source, generate a compile rule based on extension
define GEN_RULE
$(call src_to_obj,$(1)): $(1)
	@mkdir -p $$(dir $$@)
	$(2) $(3) -c $$< -o $$@
endef

$(foreach s,$(PFC_SRCS),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))
$(foreach s,$(filter %.mm,$(PFC_SRCS)),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# SDK
$(foreach s,$(FB2K_SDK_SRCS),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# Helpers
$(foreach s,$(FB2K_HELPERS_SRCS),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# Mac helpers - .m files use OBJCFLAGS, .mm files use CXXFLAGS
$(foreach s,$(filter %.m,$(FB2K_MAC_HELPERS_SRCS)),$(eval $(call GEN_RULE,$(s),$(CC),$(OBJCFLAGS))))
$(foreach s,$(filter %.mm,$(FB2K_MAC_HELPERS_SRCS)),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# Shared
$(foreach s,$(SHARED_SRCS),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# Component client
$(foreach s,$(CLIENT_SRCS),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# Plugin
$(foreach s,$(PLUGIN_SRCS),$(eval $(call GEN_RULE,$(s),$(CXX),$(CXXFLAGS))))

# ===================
# Clean
# ===================

clean:
	rm -rf $(BUILD_DIR)
	@echo "Cleaned."
