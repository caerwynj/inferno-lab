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
		Acmewin.writebody(x + "\n");
		getfeeds(x.split("(")[0]);
		tagmode = false;
		return true;
	}
		
	return false;
}
