# Lab 79 - Acme Javascript client

I'm excited about today's lab. I hope others pick up on this 
and experiment with it
because I think some cool acme clients would come of it.

The idea behind this lab is to mix together acme, javascript and json web services.

I've been poking around at inferno's javascript, hoping to improve it. 
The best way of doing that is to start using it more heavily.  In earlier labs
I created a tool called js that ran javascript scripts outside of inferno. 
But without knowing what set of host objects to build it has languished.

Looking to use javascript more, I've been taking another 
look at web services APIs, and noticing
that JSON is getting strong support, especially from Google and Yahoo.
I'm pleased about this, since the SOAP stuff looked so horrid.
So I really want to pull JSON web services into inferno using javascript.
But web services
don't work too well when text is just output to the command line, they need more
interaction. 

So the natural thing to do is build an acme client. Acme clients can
be built using shell but I don't think that is ideal. Inferno shell
can really show its limits when tried to use as a programming
language. And for new users javascript is probably an easier
and more familiar language to get to grips with.

I decided In this lab I created a javascript command that includes acmewin as
a host object. I also added a host readlUrl function meant for calling json
services.  Together I hope this makes it really simple for anyone to
put together an acme client using data pulled from the internet.

The command is called Jwin and is envoked with the name of
a javascript file.

	% Jwin -f file.js

It opens one window for the script to operate on.

I created an Acmewin host object, that is instantiated before the script
is run. It has methods that mirror the acmewin library, read, writebody,
tagwrite, name, clean, select, setaddr, replace, readall.

It also has to event properties, onlook and onexec which should
be assigned functions if you want to react to mouse clicks
of the middle and right buttons.

Here's the simplest javascript client.

	Acmewin.onexec = function(x) {
		Acmewin.writebody("onexec:" + x + "\n");
	}
	
	Acmewin.onlook = function(x) {
		Acmewin.writebody("looking at:" + x + "\n");
	}

I still need to write a postUrl. I'd like a blogger interface myself.
Even though most google APIs allow read access using JSON they
only allow posts in Atom format. But given the Javascript object
it shouldn't be hard to build the xml string for the post.

The web access is through svc/webget/webget, so this
should be started before using Jwin. 

Below is a longer example to give you more of a flavor
of an acmeclient written in javascript. Try this out and
see how fast you can come up with you own acme client.

	var undefined;
	var user = "caerwyn";
	var baseurl = "http://del.icio.us/feeds/json/";
	var count = "?count=20";
	
	var tagmode = false;
	function getfeeds(tag)
	{
		if(tag != undefined){
			var s = System.readUrl(baseurl + user + "/" + tag);
		}else {
			var s = System.readUrl(baseurl + user + count);
		}
		eval(s);
		for (var i =0, item; item = Delicious.posts[i]; i++) {
			Acmewin.writebody(i + "/\t" + item.d + "\n");
		}
	}
	
	function gettags()
	{
		var s = System.readUrl(baseurl + "tags/" + user);
		eval(s);
		for(var i in Delicious.tags){
			Acmewin.writebody(i + "(" + Delicious.tags[i] +")\n");
		}	
	}
	
	getfeeds();
	Acmewin.tagwrite(" Posts Tags ");
	Acmewin.name("del.icio.us/caerwyn");
	
	Acmewin.onexec = function(cmd) {
		if(cmd == "Posts"){
			Acmewin.replace(",", "");
			getfeeds();
			tagmode = false;
			return true;
		}else if(cmd == "Tags"){
			Acmewin.replace(",", "");
			gettags();
			tagmode = true;
			return true;
		}
		return false;
	}
	
	Acmewin.onlook = function(x) {
		var n = parseInt(x);
		if(n >=0 && n < Delicious.posts.length){
			Acmewin.writebody(Delicious.posts[n].u + "\n");
			return true;
		}
		if(tagmode){
			Acmewin.replace(",", "");
			getfeeds(x.split("(")[0]);
			tagmode = false;
			return true;
		}
			
		return false;
	}
