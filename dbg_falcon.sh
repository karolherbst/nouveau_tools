#!/bin/bash

# we need this for +(0) substitutions
shopt -s extglob

FALCON_BASE=10a000
FALCON_BINARY=/home/karol/Dokumente/repos/nouveau/drm/nouveau/nvkm/subdev/pmu/fuc/gf119.fuc4.h

declare -A instructionMap

function parseFalconImage {
	while read line; do
		local address=${line%%:*}
		local value=${line#*:}
		address=${address##+(0)}
		address=${address:-0}
		instructionMap[$address]=${value##+( )}
	done < <(cat "$FALCON_BINARY" | grep _code -A9999999 | grep 0x | grep , | cut -d, -f1 | envydis -n -m falcon -V fuc4 -w | grep -v -e '^[[:space:]]*$')
}

function toHex {
	echo $(printf "%x" $1)
}

function mask {
	nvamask $(toHex $((16#$FALCON_BASE+16#$1)) ) $2 $3
}

function peek {
	local value=$(nvapeek $(toHex $((16#$FALCON_BASE+16#$1)) ) | cut -d: -f2)
	if [ "$value" == "..." ]; then
		value="00000000"
	fi
	echo $value
}

function poke {
	nvapoke $(toHex $((16#$FALCON_BASE+16#$1)) ) $2
}

function instructionAt {
	local address=${1##+(0)}
	local lastAddress=$address
	local instr=""
	address=${address:-0}
	while [[ -z $instr ]]; do
		lastAddress=$address
		instr=${instructionMap[$lastAddress]}
		address=$(toHex $((16#$address-1)) )
	done
	echo "$instr"
}

function dumpBinary {
	cat "$FALCON_BINARY" | grep _code -A9999999 | grep 0x | grep , | cut -d, -f1 | envydis -n -m falcon -V fuc4 -w | grep -v -e '^[[:space:]]*$'
}

function listBreakpoints {
	local regV=$(peek 98)
	regV=$(toHex $((16#$regV&16#007fffff)) )
	printf "Breakpoint at: 0x%s (%s)\n" $regV "$(instructionAt $regV)"
}

function status {
	pc=$(readReg pc)
	printf '$pc: '; printf "%s (%s)\n" $pc "$(instructionAt $pc)"
	printf '$sp: '; readReg sp
}

function setBreakpoint {
	poke 98 $(toHex $(($1|16#80000000)) )
}

function readReg {
	local reg=$1
	case $1 in
	iv0)		reg=16 ;;
	iv1)		reg=17 ;;
	iv2)		reg=18 ;;
	tv)		reg=19 ;;
	sp)		reg=20 ;;
	pc)		reg=21 ;;
	xcbase)		reg=22 ;;
	xdbase)		reg=23 ;;
	flags)		reg=24 ;;
	cx)		reg=25 ;;
	cauth)		reg=26 ;;
	ctargets)	reg=27 ;;
	tstatus)	reg=28 ;;
	esac

	if [[ -z $2 ]]; then
		poke 200 $(toHex $((16#8|($reg&16#1f)<<8)) )
		peek 20c
	else
		poke 208 $2
		poke 200 $(toHex $((16#9|($reg&16#1f)<<8)) )
	fi
}

function readwritedataio {
	poke 204 $3
	if [[ -z $4 ]]; then
		poke 200 $(toHex $((16#$1|2<<6)) )
		peek 20c
	else
		poke 208 $4
		poke 200 $(toHex $((16#$2|2<<6)) )
	fi
}

function data {
	readwritedataio a b $1 $2
}

function io {
	readwritedataio c d $1 $2
}

function dbg_continue {
	if [[ -z $1 ]]; then
		poke 200 1
	else
		poke 204 $1
		poke 200 2
	fi
}

function dbg_break {
	poke 200 0
}

function dbg_step {
	if [[ -z $1 ]]; then
		poke 200 5
	else
		poke 204 $1
		poke 200 6
	fi
}

if [[ $# -gt 0 ]]; then
	parseFalconImage
	key="$1"
	case $key in
	b|break)
		dbg_break
		status
		;;
	bp|breakpoint)
		setBreakpoint $2
		;;
	c|continue)
		dbg_continue $2
		;;
	data)
		data $2 $3
		;;
	dump)
		dumpBinary
		;;
	io)
		io $2 $3
		;;
	reg)
		readReg $2 $3
		;;
	status)
		status
		;;
	step)
		dbg_step $2
		status
		;;
	esac
else
	status
fi
