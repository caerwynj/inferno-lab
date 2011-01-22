#!/dis/sh

load string

<> /chan/webget {
	phrase=$"*
	x := "{sed 's/PHRASE/' ^ $phrase ^'/' /usr/caerwyn/doSpellingSuggestion.xml}
	size=${len $x}
	echo POST∎ ^ $size ^ ∎0∎http://api.google.com/search/beta2∎text/xml∎no-cache >[1=0]
	echo -n $x >[1=0]
	getlines {f = ${unquote $line}
		if { ~ ${hd $f} OK} {
			f = ${tl $f}
			read ${hd $f}
			exit
		} {exit}
	}
} $* | sed -n '/return/s/<[^>]*>//gp'
