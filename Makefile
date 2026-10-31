# Makefile for agonAMP (for building on a PC; see README.md for building
# on the Agon itself).
#
# Needs agon-ez80asm (https://github.com/AgonPlatform/agon-ez80asm) built
# for the host. Set EZ80ASM if it is not on the PATH.
#
# The assembler looks for include files relative to the current
# directory, so each program is assembled from its own directory.
EZ80ASM ?= ez80asm
LIB = lib/pt3play.asm lib/pt3tab.inc lib/pt3ts.asm lib/psgplay.asm \
      lib/stcplay.asm \
      lib/pt2play.asm lib/pt1play.asm lib/ascplay.asm lib/stpplay.asm \
      lib/sqtplay.asm lib/pscplay.asm lib/notetab.inc \
      lib/ymplay.asm lib/lh5.asm lib/ayfplay.asm lib/z80emu.asm \
      lib/z80tab.inc lib/ayvdp.asm \
      lib/tick50.asm lib/libsupport.asm
SRC = src/agonamp.asm src/ui.asm src/pattern.asm src/patother.asm \
      src/files.asm src/util.asm src/spectrum.asm src/spectab.inc \
      src/config.asm \
      src/equs.inc src/vk.inc

all: agonamp.bin

agonamp.bin: $(SRC) $(LIB)
	cd src && $(EZ80ASM) agonamp.asm ../agonamp.bin

# The library example. Put a module called tune.pt3 in examples first.
examples/playtune.bin: examples/playtune.asm examples/tune.pt3 $(LIB)
	cd examples && $(EZ80ASM) playtune.asm playtune.bin

# The replayer test programs (see the compare scripts in test).
test/pt3test.bin: test/pt3test.asm $(LIB)
	cd src && $(EZ80ASM) ../test/pt3test.asm ../test/pt3test.bin

test/psgtest.bin: test/psgtest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/psgtest.asm ../test/psgtest.bin

test/stctest.bin: test/stctest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/stctest.asm ../test/stctest.bin

test/pt2test.bin: test/pt2test.asm $(LIB)
	cd src && $(EZ80ASM) ../test/pt2test.asm ../test/pt2test.bin

test/pt1test.bin: test/pt1test.asm $(LIB)
	cd src && $(EZ80ASM) ../test/pt1test.asm ../test/pt1test.bin

test/asctest.bin: test/asctest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/asctest.asm ../test/asctest.bin

test/stptest.bin: test/stptest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/stptest.asm ../test/stptest.bin

test/sqttest.bin: test/sqttest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/sqttest.asm ../test/sqttest.bin

test/psctest.bin: test/psctest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/psctest.asm ../test/psctest.bin

test/pt3tstest.bin: test/pt3tstest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/pt3tstest.asm ../test/pt3tstest.bin

# The sound layer tests (see test/aycheck.py).
test/aytest.bin: test/aytest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/aytest.asm ../test/aytest.bin

test/aytest2.bin: test/aytest2.asm $(LIB)
	cd src && $(EZ80ASM) ../test/aytest2.asm ../test/aytest2.bin

# The LH5, YM/VTX and AY file tests (see test/lh5check.py,
# test/ymcheck.py and test/ayfcheck.py).
test/lh5test.bin: test/lh5test.asm lib/lh5.asm
	cd src && $(EZ80ASM) ../test/lh5test.asm ../test/lh5test.bin

test/ymtest.bin: test/ymtest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/ymtest.asm ../test/ymtest.bin

test/ayftest.bin: test/ayftest.asm $(LIB)
	cd src && $(EZ80ASM) ../test/ayftest.asm ../test/ayftest.bin

# The Z80 emulator's decoding tables are made by a script.
lib/z80tab.inc: tools/mkz80tab.py
	python3 tools/mkz80tab.py > lib/z80tab.inc

# The song length tests (see test/compare_len.sh): make test/lenpt3.bin etc.
# (test/lents.bin is the TurboSound one.)
test/len%.bin: test/len%.asm $(LIB)
	cd src && $(EZ80ASM) ../test/len$*.asm ../test/len$*.bin

clean:
	rm -f agonamp.bin examples/playtune.bin test/*.bin

.PHONY: all clean