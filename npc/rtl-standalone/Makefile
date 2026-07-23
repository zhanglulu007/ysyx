PROJECT_DIR := $(abspath $(CURDIR))
NPC_ROOT := $(abspath $(PROJECT_DIR)/..)
WORKBENCH_ROOT := $(abspath $(NPC_ROOT)/..)
SIM_ROOT := $(NPC_ROOT)/csrc_standalone
NEMU_HOME := $(WORKBENCH_ROOT)/nemu

ifeq ($(VERILATOR_ROOT),)
  VERILATOR := verilator
else
  export VERILATOR_ROOT
  VERILATOR := $(VERILATOR_ROOT)/bin/verilator
endif

TOP := top
TOP_CLASS := Vtop
BUILD_DIR := $(PROJECT_DIR)/build
OBJ_DIR := $(BUILD_DIR)/obj_dir
WAVE_DIR := $(PROJECT_DIR)/wave

RTL_SRCS := $(sort $(wildcard $(PROJECT_DIR)/vsrc/*.v) $(wildcard $(PROJECT_DIR)/vsrc/*.sv))
ADAPTER_SRCS := $(sort $(wildcard $(PROJECT_DIR)/csrc/adapter/*.cpp))
SHARED_CORE_SRCS := $(filter-out \
  $(SIM_ROOT)/core/cpu.cpp \
  $(SIM_ROOT)/core/npc.cpp \
  $(SIM_ROOT)/core/ftrace_dpi.cpp, \
  $(wildcard $(SIM_ROOT)/core/*.cpp))
SHARED_SRCS := \
  $(SIM_ROOT)/main.cpp \
  $(SHARED_CORE_SRCS) \
  $(wildcard $(SIM_ROOT)/sdb/*.cpp) \
  $(wildcard $(SIM_ROOT)/utils/*.cpp) \
  $(wildcard $(SIM_ROOT)/trace/*.cpp)

FST ?= 0
TRACE ?= 0
DIFFTEST ?= 0
DIFFTEST_SO ?= $(NEMU_HOME)/build/riscv32-nemu-interpreter-standalone-so

PROG ?= test/mem.bin
ELF ?=
BATCH ?= -b

PROG_ABS := $(abspath $(PROG))
ELF_ABS := $(if $(ELF),$(abspath $(ELF)))

VERILATOR_FLAGS := \
  --top-module $(TOP) \
  --x-assign fast --x-initial fast \
  --timescale "1ns/1ns" --no-timing --autoflush \
  -Wno-fatal

EXTRA_CFLAGS :=
VERILATOR_TRACE_FLAGS :=

ifeq ($(FST),1)
  VERILATOR_TRACE_FLAGS += --trace-fst --trace-structs
  EXTRA_CFLAGS += -DENABLE_FST
endif

ifeq ($(TRACE),1)
  EXTRA_CFLAGS += -DENABLE_TRACE
endif

ifneq ($(ELF),)
  ELF_ARG := -e $(ELF_ABS)
endif

ifeq ($(DIFFTEST),1)
  DIFFTEST_ARG := -d $(DIFFTEST_SO)
endif

SDL_CFLAGS := $(shell sdl2-config --cflags)
SDL_LIBS := $(shell sdl2-config --libs) -lSDL2_image -lSDL2_ttf

define VERILATE_CMD
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_TRACE_FLAGS) \
	  -cc --exe --build -j \
	  -CFLAGS "-std=c++14 -O3 \
	    -I$(SIM_ROOT) \
	    -I$(NEMU_HOME)/tools/capstone/repo/include \
	    -I$(NEMU_HOME)/include \
	    $(SDL_CFLAGS) $(EXTRA_CFLAGS)" \
	  -LDFLAGS "-lreadline -ldl $(SDL_LIBS)" \
	  $(RTL_SRCS) $(ADAPTER_SRCS) $(SHARED_SRCS) \
	  --Mdir $(OBJ_DIR)
endef

all: build

show-config:
	@echo "PROJECT_DIR=$(PROJECT_DIR)"
	@echo "RTL_DIR=$(PROJECT_DIR)/vsrc"
	@echo "SIM_ROOT=$(SIM_ROOT)"
	@echo "FST=$(FST) TRACE=$(TRACE) DIFFTEST=$(DIFFTEST)"
	@echo "PROG=$(PROG_ABS) ELF=$(ELF_ABS)"

lint:
	$(VERILATOR) --lint-only --top-module $(TOP) -Wall -Wno-fatal $(RTL_SRCS)

build:
	@mkdir -p $(BUILD_DIR) $(WAVE_DIR)
	@echo "-- BUILD rtl-standalone [FST=$(FST) TRACE=$(TRACE)] --"
	$(VERILATE_CMD)

run: build
	@if [ ! -f "$(PROG_ABS)" ]; then \
	  echo "Error: program '$(PROG_ABS)' not found."; exit 1; \
	fi
	@if [ "$(DIFFTEST)" = "1" ] && [ ! -f "$(DIFFTEST_SO)" ]; then \
	  echo "Error: DiffTest REF '$(DIFFTEST_SO)' not found."; exit 1; \
	fi
	@echo "-- RUN rtl-standalone [DIFFTEST=$(DIFFTEST)] --"
	@cd $(NPC_ROOT) && \
	  $(OBJ_DIR)/$(TOP_CLASS) $(PROG_ABS) \
	  -l $(PROJECT_DIR)/npc.log $(ELF_ARG) $(DIFFTEST_ARG) $(BATCH)

clean:
	-rm -rf $(BUILD_DIR) $(WAVE_DIR) $(PROJECT_DIR)/npc.log

.PHONY: all show-config lint build run clean
