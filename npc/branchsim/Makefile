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
	@rm -f tests/static.actual tests/override.actual

clean:
	rm -f $(TARGET) tests/*.actual

.PHONY: run test clean
