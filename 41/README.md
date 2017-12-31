# NAME
lab 41 - venti lite

# NOTES
I've taken another look recently at venti and the ideas from the venti paper.

Venti is a data log and index. The index maps a sha1 hash of a clump of data to the offset of the clump in the log. Clumps are appended to the log after being compressed and wrapped with some meta-data. A sequence of clumps make an arena, and all the arenas, possibly spread over several disks, make up the whole data log. There is enough information in the data log to recreate the index, if neccessary.

The above is my understanding of Venti so far after reading the code and paper. There is a lot more complexity in it's implementation. There are details about the caches, the index, the compression scheme, the blocking and partitioning of disks, and so on. I will ignore these details for now. Although the whole of venti could be ported to Inferno, I want to look at it without getting bogged down in too many details too early.

Reasoning about Venti in the context of Inferno I tried to do some simple analog of Venti using Inferno sh(1). The two basic functions of Venti are the read of a clump using the hash, called a score, to locate it, and writing a clump getting a score in return. I created two sh functions, putclump and getclump.

It is easier to reuse than to reinvent. I use gzip for compression, puttar for packaging a clump, sha1sum to hash the clump, and dbm as the index. Here's the code for putclump.

	#!/dis/sh
	load expr
	if {! ~ $#* 2} {
	 echo usage: putclump type file > /fd/2
	 exit
	}
	
	type := $1
	file := $2
	Maxclumpsize=57344
	(perm device inst 
	  owner group 
	  size rest) := `{ls -l $file}
	if {ntest ${expr $size $Maxclumpsize gt }} {
	 echo file too big > /fd/2
	 exit
	}
	
	(sha f) := `{sha1sum $file}
	tmp:=/tmp/$sha.$type
	o := `{dbm/fetch idx $sha >[2] /dev/null}
	if{~ $#o 0} {
	 (perm device inst owner 
	          group offset rest) := `{ls -l arena}
	 cat $file > $tmp
	 puttar  $tmp |gzip >> arena
	  echo $sha $offset |dbm/store idx
	}
	rm -f $tmp
	echo $sha

To use it, create an arena file, and the index files first.

	% touch arena idx.pag idx.dir
	% echo this is a test > t1
	% putclump Datatype t1
	...

And to prove it works add the same file again and get the same score back.

I can get the contents back out using getclump. Here is how getclump is defined.

	#!/dis/sh
	
	Maxclumpsize=57344
	score := $1
	offset := `{dbm/fetch idx $score}
	read -o $offset $Maxclumpsize < arena |
	   gunzip | 
	   gettarentry {cat}

A file must be less than the Maxclumpsize. If I store a set of files I get a list of scores back. I can write this list to a file and write the list back with a different clump type: Pointertype0. Then I store the final score as a file with one score entry and call this the Roottype.

	% { for (i in *.b) {putclump Datatype $i} } > t1
	% putclump Pointertype0 > t2
	% putclump Roottype t2 > rootscore
	
This is more or less the hash tree described in the paper. The data log can be scanned, for example to retrieve all the Roottype scores.


	% gunzip < arena| gettarentry {echo $file}

This implementation of putclump and getclump could quite easily be moved from shell into limbo also serving the Venti protocol for a rudimentary venti server.
