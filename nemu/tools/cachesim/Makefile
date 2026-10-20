CC ?= gcc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Werror
TARGET := cachesim

all: $(TARGET)

$(TARGET): cachesim.c
	$(CC) $(CFLAGS) -o $@ $<

dse: $(TARGET)
	./run-dse.sh

clean:
	rm -f $(TARGET) dse.csv

.PHONY: all dse clean
