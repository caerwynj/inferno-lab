# NAME
lab 52 - text files

# NOTES
Some limbo programs can be replaced with shell one liners, and others can be replaced with more general programs that reduce the limbo line count but increase functionality. I'll look at the few I've discovered.

The /prog filesystem exposes a textual interface that allows existing software tools to work with it. This implies I do not need a custom set of limbo tools to read and write to this filesystem. For example, ps is a 61 line limbo program, but I can do the same thing in one line of shell,

	fn ps {sed '' /prog/*/status |sort -n}

This is the great power of Inferno. Simple textual interfaces exposed as files and a small set of software tools working together. Therefore, I can also try rewriting kill and broke. In this case I make the functionality more like Plan 9. Each command writes to output the commands that can be sent back to the shell to actually perform the kill action.

	fn kill {
	 sed -n '/' ^ $1 ^ '/s/^ +([0-9][0-9]*) +(.*)/echo '^
	'kill >\/prog\/\1\/ctl # \2/p' /prog/*/status
	}

	fn broke {
	 sed -n '/broke/s/^ +([0-9][0-9]*) +(.*)/echo '^
	'kill >\/prog\/\1\/ctl # \2/p' /prog/*/status
	}

This reduces the limbo line count a little more. It also is more suggestive of what can be done when filesystems are implemented with an appreciation of the encompassing system. Take this example from Plan 9 translated for Inferno which shows who is logged into the system:

	fn who {
	 ps | sed '/Broken/d
	 /Exiting/d
	 s% +[0-9]+ +[0-9]+ +([a-zA-Z0-9]+) +.*$%\1%' | 
	          sort | uniq
	}

The /net filesystem also exposes a textual interface. I can implement netstat as a script too (almost, it doesn't include the user name, but i wanted to keep it short).

	fn netstat {
	  for i in /net/*/[0-9] {
	    echo  $i `{cat $i/status $i/local $i/remote}
	  }
	}

Lookman has bothered me because it could be more general. This is obvious if you're aware of the `look` command from Plan 9. Why not just port look and wrap it in a shell script to implement lookman?

	fn lookman {
	 look $* /man/index | sed 's/^.* //' |sort 
	          |uniq |sed 's;/man/;;
	           s;(.*)/(.*);man \1 \2 # \2(\1);'
	}

I've again taken the idea from Plan 9. In my opinion this is better than the Inferno original. It prints the man page reference syntax, which works beautifully with Acme plumbing. I've included the source for the look port in this lab's files.

Another not-general-enough implementation is src. It is supposed to print the source file for a named dis file. The problem here is that the dis file is binary format so it needs a limbo library to extract the source file name. How is this done in Plan 9's src script? It uses adb. Well I don't have that. But I do have mdb. Maybe I should extend it with a few commands to examine a dis file. This would replace wm/rt which doesn't really fit in the system because it can't be used within scripts. So now src can be made a script, and changed slightly

	fn src {
	 file := $1
	 if {ftest -e $file} {
	  mdb $file '$s'
	 } {ftest -e $file.dis} {
	  mdb $file.dis '$s'
	 } {ftest -e /dis/$file} {
	  mdb /dis/$file '$s'
	 } {ftest -e /dis/$file.dis} {
	  mdb /dis/$file.dis '$s'
	 } 
	}

Okay, one more. This is a script to implement calendar but not as feature rich as the UNIX version. The calendar file is a list of multi-line records separated by blank lines, with any line in the record matching the date format 20060203, or just 0203 for recurring appointments, for example. This uses the xp command from lab 50.

	fn calendar {
	smon:='s/Jan/01/
	 s/Feb/02/
	 s/Mar/03/
	 s/Apr/04/
	 s/May/05/
	 s/Jun/06/
	 s/Jul/07/
	 s/Aug/08/
	 s/Sep/09/
	 s/Oct/10/
	 s/Nov/11/
	 s/Dec/12/'
	 (d m md tim tz yr) := `{date |sed $smon}
	 xp ',x/(.+\n)+/ g/('^ $yr ^')?'^ $m ^ 
	   $md  ^ '/p' $home/calendar
	}

Textual manipulation with pattern-action languages is the hallmark of Plan9 and Inferno. File systems that expose textual interfaces play well with the rest of the system. However, sometimes in Inferno it feels like this isn't exploited or is hidden below the surface. Either because commands are implemented in Limbo when they don't need to be, or because a more general tool could exist based around the command line and not the wm GUI.

I have made the mistake in earlier labs of implementing tools around binary formats, or exposing binary interfaces from filesystems. After looking more closely at the elegance of /prog and /net I'd try to emulate their example.
