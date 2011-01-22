#!/dis/sh

stow=$1
hold=/n/hold
branch = `{cat $hold^/HEAD}
log = $hold^/logs/^ $branch

if {! ftest -e $stow} {
	echo $stow does not exist >/fd/2
	exit
}

hold/holdfs $stow

tmp := /tmp/stow.${pid}
install/updatelog  -c -S -r /mnt/arch  $log  appl > $tmp

#hold/applylog -n -v -s $log '#U' /n/hold < $stow

exit
getlines {
	(sec seq v file sf mode uid gid mtime size sha) := ${split ' ' $line}
	echo diff -c /^$file /mnt/arch/^$file
	diff -c /^$file /mnt/arch/^$file
} < $tmp


rm -f $tmp
