.DEFAULT_GOAL = app

# Add necessary options if the target is a shared library
ifeq ($(SHARE),1)
SO = -so
CFLAGS  += -fPIC -fvisibility=hidden
LDFLAGS += -shared -fPIC
endif

WORK_DIR  = $(shell pwd)
BUILD_DIR = $(WORK_DIR)/build

INC_PATH := $(WORK_DIR)/include $(INC_PATH)
OBJ_DIR  = $(BUILD_DIR)/obj-$(NAME)$(SO)
BINARY   = $(BUILD_DIR)/$(NAME)$(SO)

# --- Dual REF .so build (standalone + ysyxsoc) ---
# 当用户在 menuconfig 中选择了 "Shared object" 并启用
# DIFFTEST_DUAL_BUILD 时，除当前配置的主 .so 外，还自动构建
# 另一个 YSYXSOC 状态相反的变体。
ifdef CONFIG_DIFFTEST_DUAL_BUILD
  ifeq ($(CONFIG_YSYXSOC),y)
    SECOND_NAME = $(GUEST_ISA)-nemu-$(ENGINE)-standalone
    SECOND_DEFCONFIG = riscv32-standalone_defconfig
  else
    SECOND_NAME = $(GUEST_ISA)-nemu-$(ENGINE)-ysyxsoc
    SECOND_DEFCONFIG = riscv32-ysyxsoc-so_defconfig
  endif
  SECOND_SO = $(BUILD_DIR)/$(SECOND_NAME)-so
endif

# Compilation flags
ifeq ($(CC),clang)
CXX := clang++
else
CXX := g++
endif
LD := $(CXX)
INCLUDES = $(addprefix -I, $(INC_PATH))
CFLAGS  := -O2 -MMD -Wall -Werror $(INCLUDES) $(CFLAGS)
LDFLAGS := -O2 $(LDFLAGS)

OBJS = $(SRCS:%.c=$(OBJ_DIR)/%.o) $(CXXSRC:%.cc=$(OBJ_DIR)/%.o)

# Compilation patterns
$(OBJ_DIR)/%.o: %.c
	@echo + CC $<
	@mkdir -p $(dir $@)
	@$(CC) $(CFLAGS) -c -o $@ $<
	$(call call_fixdep, $(@:.o=.d), $@)

$(OBJ_DIR)/%.o: %.cc
	@echo + CXX $<
	@mkdir -p $(dir $@)
	@$(CXX) $(CFLAGS) $(CXXFLAGS) -c -o $@ $<
	$(call call_fixdep, $(@:.o=.d), $@)

# Depencies
-include $(OBJS:.o=.d)

# Some convenient rules

.PHONY: app clean

app: $(BINARY)
ifdef CONFIG_DIFFTEST_DUAL_BUILD
app: $(SECOND_SO)
endif

$(BINARY):: $(OBJS) $(ARCHIVES)
	@echo + LD $@
	@$(LD) -o $@ $(OBJS) $(LDFLAGS) $(ARCHIVES) $(LIBS)

# 第二份 REF .so: 切换 defconfig 后递归 make, 完成后恢复原配置
# 构建失败时也会恢复 .config (通过 trap)
ifdef CONFIG_DIFFTEST_DUAL_BUILD
$(SECOND_SO): $(BINARY)
	@echo "=== Building second REF .so variant: $(SECOND_NAME) ==="
	@cp $(NEMU_HOME)/.config $(NEMU_HOME)/.config.dual_bak
	@cp $(NEMU_HOME)/configs/$(SECOND_DEFCONFIG) $(NEMU_HOME)/.config
	@$(MAKE) -s -C $(NEMU_HOME) SHARE=1 NAME=$(SECOND_NAME) app || \
		{ rc=$$?; mv $(NEMU_HOME)/.config.dual_bak $(NEMU_HOME)/.config; exit $$rc; }
	@mv $(NEMU_HOME)/.config.dual_bak $(NEMU_HOME)/.config
	@echo "=== Second REF .so done: $@ ==="
endif

clean:
	-rm -rf $(BUILD_DIR)
