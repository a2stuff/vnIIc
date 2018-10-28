
CC65 = ~/dev/cc65/bin
CAFLAGS = --target apple2enh --list-bytes 0
CCFLAGS = --config apple2-asm.cfg

TARGETS = \
	client.bin

.PHONY: clean all
all: $(TARGETS)

HEADERS = $(wildcard *.inc)

clean:
	rm -f *.o
	rm -f *.list
	rm -f $(TARGETS)

%.o: %.s $(HEADERS)
	$(CC65)/ca65 $(CAFLAGS) $(DEFINES) --listing $(basename $@).list -o $@ $<

%.bin: %.o
	$(CC65)/ld65 $(CCFLAGS) -o $@ $<
