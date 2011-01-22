#!/dis/sh
load expr arg string

args := $*
hold := /n/hold
(arg
	d+ {hold = $arg}
	'*' {echo unknown option $opt}
	- $args
)

sha := $1
(a b) := ${slice 0 2 $sha} ${slice 2 40 $sha}

files := `{ls $hold/objects/$a/$b^* >[2] /dev/null}
if {~ $#files 0} {echo not found > /fd/2; raise 'not found'} {~ $#files 1} {gunzip < $files } {echo more than one $files > /fd/2; raise 'too many'}
