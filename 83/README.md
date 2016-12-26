#NAME
lab 83 - lcmd local cpu

#NOTES
While thinking of the Simple Grid Tutorial Part 1 and Part 2, I wondered whether I could implement the equivalent of rcmd(1) but for a local emu launched using os(1). For example,

	 lcmd math/linbench 100

would launch a new emu, export the local fs to it through a pipe rather than a network socket, and run the command in that namespace. The idea seemed simple, no apparent obstacles, but it actually took me a couple of evenings to get it to work. So I'm posting it more because of the effort rather than its value.

First lets look at what rcmd does, ignoring the networking. Given its arguments it builds a string, calculates its length + 1, and writes the length then the string to a file descriptor, then exports the local namespace to the same file descriptor. Well that part is easy to do in sh(1). Here it is as a braced block assuming all work is done on file descriptor 1.

	fn lcmd {
	 load expr string
	 args := $*
	 s := sh -c ${quote $"args}
	 echo ${expr ${len $"s} 1 + } 
	 echo $s
	 export / /fd/1
	}

We can test that,

	 lcmd {ls } | auxi/rstyxd

Now, instead of running rstyxd in the current VM, I want to run another instance and run in it that. This is where it gets complicated. You might think this might work,

 
	 lcmd {ls} | os emu auxi/rstyxd

It doesn't because os treats stdin as read only, stdout as write only. Because export(1) needs to read and write on one file descriptor, and so does rstyxd(8), we need to setup extra pipes, both on the local end and the remote end.

Another problem presents itself in emu. At startup rstyxd will see /dev/cons as stdin. But I'd need to bypass the keyboard handling and get the direct stdin from the pipe. We see the answer to that in /dev,

	% ls -l /dev/host*
	--rw-r--r-- c 0 caerwyn caerwyn 0 Oct 30 22:43 /dev/hostowner
	---w--w--w- c 0 caerwyn caerwyn 0 Oct 30 22:43 /dev/hoststderr
	--r--r--r-- c 0 caerwyn caerwyn 0 Oct 30 22:43 /dev/hoststdin
	---w--w--w- c 0 caerwyn caerwyn 0 Oct 30 22:43 /dev/hoststdout

This looks good but when I tried them they were not fully implemented in the current emu. The details are not interesting. I fixed that in the acme-sac tree and committed it.

Finally, we can build our full lcmd

	fn lcmd {
	 load std expr string
	 pctl forkns
	 args := $*
	 s := sh -c ${quote $"args}
	 bind '#|' /tmp/lpipe
	 
	 {
	  echo ${expr ${len $"s} 1 + }  >/fd/0;  
	  echo $s >/fd/0; 
	  export / /fd/0
	 } <>/tmp/lpipe/data    &
	 
	 os -d 'd:/acme-sac' d:/acme-sac/sys/Nt/386/bin/icell.exe -c1  sh -c '
	  bind  ''#|'' /tmp/pipes; 
	  cat /tmp/pipes/data > /dev/hoststdout& 
	  cat /dev/hoststdin > /tmp/pipes/data& 
	  auxi/rstyxd <>/tmp/pipes/data1 >[2] /dev/null;  
	  echo halt > /dev/sysctl' < /tmp/lpipe/data1 >/tmp/lpipe/data1
	}
Heh!

I'm using icell.exe built using the cell config from acme-sac. This is a really small emu configuration. The directories /tmp/pipes, /tmp/lpipe are assumed to exist.

From this definition we can replace rcmd with lcmd in the commands for rsplit and lk in the Grid Tutorial Part 2 and get emu tools for multicores without the setup required for the grid.
