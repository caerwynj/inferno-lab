#!/dis/sh

# Given the address of two logs
# Create a list of files that differ.

tmp1 := /tmp/difflog1.${pid}
tmp2 := /tmp/difflog2.${pid}

hold/getclump $1 > $tmp1
hold/getclump $2 > $tmp2

hold/holdfs -m /n/$1 $tmp1
hold/holdfs -m /n/$2 $tmp2

/appl/cmd/hold/applylog -x -s  $tmp1 /tmp /tmp < $tmp2 | getlines {
	(file s1 s2) := ${split ' 	' $line}
	if {~ $file '*.dis' '*.sbl'} {
		echo $line
	} { 
		diff -u /n/$1/$file /n/$2/$file
	} 
}

rm -f $tmp1 $tmp2 $tmp3 $tmp4
