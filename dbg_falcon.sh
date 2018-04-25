#!/bin/bash

# we need this for +(0) substitutions
shopt -s extglob

FALCON_BASE=41a000
FALCON_TYPE=fuc5
PATH="$PATH:/usr/local/bin/"

declare -A instructionMap
declare -a instructionMapOrder

function parseFalconImage {
	CODE=""

	OLD=$(peek 180)
	for i in $(seq 0 4 230); do
		poke 180 $(toHex $i)
		printf "parsing code at $(toHex $i)\n" >&2
		CODE+="$(peek 184) "
	done
	poke 180 $OLD

	while read line; do
		local address=${line%%:*}
		local value=${line#*:}
		address=${address##+(0)}
		address=${address:-0}
		instructionMap["$address"]=${value##+( )}
		instructionMapOrder+=( "$address" )
	done < <(echo "$CODE" | envydis -n -m falcon -V $FALCON_TYPE -w | grep -v -e '^[[:space:]]*$')
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
	for i in "${!instructionMapOrder[@]}"; do
		printf "%05x: %s\n" "0x${instructionMapOrder[$i]}" "${instructionMap[${instructionMapOrder[$i]}]}"
	done
}

function listBreakpoints {
	local regV=$(peek 98)
	regV=$(toHex $((16#$regV&16#007fffff)) )
	printf "Breakpoint at: 0x%s (%s)\n" $regV "$(instructionAt $regV)"
}

function status {
	pc=$(readReg pc)
	printf '$pc: '; printf "%s (%s)\n" $pc XX
# "$(instructionAt $pc)"
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

parseFalconImage
status

while true; do
	read -p "> " cmd

	cmdAr=($cmd)

	case ${cmdAr[0]} in
	b|break)
		dbg_break
		status
		;;
	bp|breakpoint)
		setBreakpoint ${cmdAr[1]}
		;;
	c|continue)
		dbg_continue ${cmdAr[1]}
		;;
	data)
		data ${cmdAr[1]} ${cmdAr[2]}
		;;
	dump)
		dumpBinary
		;;
	io)
		io ${cmdAr[1]} ${cmdAr[2]}
		;;
	reg)
		readReg ${cmdAr[1]} ${cmdAr[2]}
		;;
	status)
		status
		;;
	step)
		dbg_step ${cmdAr[1]}
		status
		;;
	quit)
		exit 0
		;;
	esac
done
