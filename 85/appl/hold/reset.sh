#!/dis/sh

hold=/n/hold
branch = `{cat $hold^/HEAD}
log = $hold^/logs/^ $branch
parent = `{sha1sum < $log}
n := `{date -n}

install/updatelog -S -r '#U' -x tmp -x mail /dev/null > $log
lsha := `{hold/putclump $log}
echo $n reset $branch $parent $lsha >> $hold/logs/log
