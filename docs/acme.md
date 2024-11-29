# Acme 
* 65 Man pages in Acme
* 94 acme content assist
* 97 acme Navigator
* 95 acme side-by-side diff
* 56 acme web
* 102 python acme client
* 103 python content assist
* 44 acme irc client
* 43 acme Wiki
* 98 acme Ctag
* 79 acme javascript
* 64 acme Chat
* 59 acme stand alone complex
* 45 full screen
* 96 acme color schemes

## Acme editor
[Acme](https://wikipedia.com/Acme_editor) is an 
editor developed for Rob Pike for the Plan 9 operating 
and inspired by the window system 
of [Oberon](https://wikipedia.com/(Oberon_system).
It is supported as part of the [plan9ports] distribution for UNIX and LINUX systems.

It [who did the conversion, when; facts!] was
translated from C to Limbo so that it could run on the Inferno OS. 

One of the unique
features of Acme compared to other editors is the 
filesystem it exposes to clients with which they interact with the editor. 
This architecture based around filesystems matches well with Inferno 
because it inherited the same ideas from Plan 9.

We'll explore several clients that use the acme file system.
They extend Acme features and integrate it with other tools,
even outside of Inferno.
These clients will provide us with a look into writing file systems
using the styx protocol, and also give us a practical enhancements
to the principal editor in Inferno.

You might feel that after using and getting familiar with Acme you know longer
need the original desktop and Tk toolkit. At the end of this chapter we configure
inferno to run Acme as the only user interface.

## Python acme client
The protocol used by Plan 9 and Inferno for distributed file systems
is called 9p2000 or Styx. They are identical and I'll mostly use the term Styx.
Styx has many implementations
and is used by systems beyond Plan 9 and Inferno.

An example implementation is on written in Python called Pyxp. 
Let us try writing a Styx client that talks to Acme.
This will also show how we can integrate with tools outside the Inferno OS
that run on the host.

I translated the acmewin limbo module I use for most acme-sac clients to python. Below is a simple example opening a new acme window and doing some operations on it.

    from acmewin import Acmewin
	win = Acmewin()
	win.writebody("hello, world!\n\n\n")
	win.tagwrite("Hello")
	win.writebody("goodbye")
	win.replace("/goodbye/", "GOODBYE")
	win.select(",")
	win.show()

Remember to export the namespace before trying it out.

	% styxlisten -A 'tcp!*!localhost' export /
	% textclient.py

I recently saw on Hacker News a repost of Peter Norvig's spelling corrector. I thought this would make an easy first trial of my python acmewin code. I implemented a client to offer spelling suggestions to an editor window. It works somewhat like my earlier acme content assist code. This client opens the event file of another window it is assisting and writes text out to its own window. In this case it offers a suggested spelling for the word currently being typed.

![109523203021-Acme-SAC](109523203021-acme-sac_3655796216_o.png)

Here's the implementation. Note that this is single threaded and it is not reading the event file of the second window. I haven't gotten that far in the Python book.

	#!/dis/python26
	
	import sys
	from acmewin import Acmewin
	import spell
	
	win = Acmewin(int(sys.argv[1]))
	outwin = Acmewin()
	
	while True:
	    (c1, c2, q0, q2, flag, nr, r) = win.getevent()
	    if c2 in "xX":
	        if flag & 2:
	            win.getevent()
	        if flag & 8:
	            win.getevent()
	            win.getevent()
	        win.writeevent(c1, c2, q0, q2)
	        if c2 == "x" and r == "Del":
	            outwin.delete()
	            break
	    if c1 == "K" and c2 == "I":
	        ch = r[0]
	        if ch in " \t\r\n":
	            outwin.replace(",", "")
	            continue
	        while q0 >= 0 and not (ch in " \t\r\n"):
	            sss = win.read(q0, q0+1)
	            if not sss:
	                # print("empty sss %d" % q0)
	                sss = " "
	            ch = sss[0]
	            q0 -= 1
	        if q0 < 0 and not(ch in " \t\r\n"):
	            q0 = 0
	        else:
	            q0 += 2
	        ss = win.read(q0,q2)
	        lastcorrect = spell.correct(ss)
	        outwin.replace(",", lastcorrect)

To run this we need to know the id of the window we are assisting, so we need a wrapper to send the $acmewin environment variable as an arg to the script. For that I have a script called SpellAssist.

	#!/dis/sh
	$home/python/assist.py $acmewin

Now that I have a simple assist-like client working I'd like to develop it further. I'd like to try having content assist for python inside acme. It should be possible to adapt the python code that implements the IDLE editor to this purpose.

big.txt the large text file used to train the spelling corrector. Note that the path is hardcoded in spell.py and should be changed locally.




## lab 59 - Acme stand alone complex
A project that has been on my mind for quite a while is to package inferno's acme as a stand alone editor. I only  had Windows in mind as a target host, but the work should be quite easy to reproduce on other hosts.

I wanted the editor to blend well with the host system, and work as a substitute for other popular programmer editors such as vim, emacs, or jedit. There were a few things I felt needed to be in place for this to work.

- cut & paste between the host and acme (lab 55)
- for acme to resize with the host window 
- dead simple packaging and install of acme on windows.

This lab covers the code to do the acme resize with host windows.

I copied the code from <b>/emu/port/devpointer.c<b> and made <b>devwmsz.c</b>. The code is almost identical except for the name changes. This device  holds a short queue of window resize events and serves a file <b>/dev/wmsize</b> that's  the same format as <b>/dev/pointer</b> with <i>x</i> and <i>y</i> fields representing the width and height of the host window.
<p>
I modified acme directly to support this new device instead of modifying wm modules, which might be more appropriate, I'm not sure. I added a new thread to /acme/gui.b to listen for resize events and resize the acme window appropriately.

<pre>
startwmsize(): chan of Rect
{
	rchan := chan of Rect;
	fd := sys->open("/dev/wmsize", Sys->OREAD);
	if(fd == nil)
		return rchan;
	sync := chan of int;
	spawn wmsizeproc(sync, fd, rchan);
	<-sync;
	return rchan;
}

wmsizeproc(sync: chan of int, 
	fd: ref Sys->FD, ptr: chan of Rect)
{
	sync <-= sys->pctl(0, nil);

	b:= array[Wmsize] of byte;
	while(sys->read(fd, b, len b) > 0){
		p := bytes2rect(b);
		if(p != nil)
			ptr <-= *p;
	}
}
</pre>
<p>
<b>/appl/acme/gui.b:/^eventproc/</b>  responds to the new event on the channel from <i>wmsizeproc</i>,
<pre>
eventproc()
{
	wmsize := startwmsize();
	for(;;) alt{
	wmsz := <-wmsize =>
		win.image = win.screen.newwindow(wmsz, 
			Draw->Refnone, Draw->Nofill);
		p := ref zpointer;
		mainwin = win.image;
		p.buttons = Acme->M_RESIZE;
		cmouse <-= p;
...
</pre>
<p>
The work is based on the emu from 20060227 Inferno release.

