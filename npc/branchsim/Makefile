CC      ?= gcc
CFLAGS  ?= -O2 -Wall -Wextra -Werror -std=c99
TARGET  := branchsim

BTRACE  ?= tests/static.btrace
ARGS    ?=

$(TARGET): branchsim.c
	$(CC) $(CFLAGS) -o $@ $<

run: $(TARGET)
	./$(TARGET) $(ARGS) $(BTRACE)

test: $(TARGET)
	./$(TARGET) tests/static.btrace > tests/static.actual
	diff -u tests/static.expected tests/static.actual
	./$(TARGET) --predict=btfn --total-insts=20 --mispredict-penalty=3 tests/override.btrace > tests/override.actual
	diff -u tests/override.expected tests/override.actual
	./$(TARGET) --btb-entries=1 tests/btb-collision.btrace > tests/btb-collision.actual
	diff -u tests/btb-collision.expected tests/btb-collision.actual
	./$(TARGET) --btb-entries=0 tests/static.btrace > tests/no-btb.actual
	diff -u tests/no-btb.expected tests/no-btb.actual
	./$(TARGET) --predictor=always-taken --btb-entries=1 tests/pc-plus-four.btrace > tests/pc-plus-four.actual
	diff -u tests/pc-plus-four.expected tests/pc-plus-four.actual
	@if ./$(TARGET) --btb-entries=3 tests/static.btrace >/dev/null 2>&1; then \
		echo "expected non-power-of-two BTB size to fail"; exit 1; \
	fi
	@rm -f tests/static.actual tests/override.actual
	@rm -f tests/btb-collision.actual tests/no-btb.actual tests/pc-plus-four.actual

clean:
	rm -f $(TARGET) tests/*.actual

.PHONY: run test clean
