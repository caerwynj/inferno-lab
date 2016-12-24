# NAME
lab 102 - python acme client

# NOTES
A recent post to 9phackers announced Pyxp, another implementation of Styx in Python.

I immediately downloaded Pyxp and tried it out. I had no trouble using it so I started thinking about python clients I could write. Python is still new to me so writing a styx client was an excuse to get more practice.

I started with an acme client. I translated the acmewin limbo module I use for most acme-sac clients to python. Below is a simple example opening a new acme window and doing some operations on it.

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

![109523203021-Acme-SAC](http://www.flickr.com/photos/caerwyn/3655796216/)

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

#FILES
inferno-lab/102 
big.txt the large text file used to train the spelling corrector. Note that the path is hardcoded in spell.py and should be changed locally.