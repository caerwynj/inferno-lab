# lab 61 - javascript

In this lab I wanted to get a standalone javascript interpreter for general scripting use within inferno.

There is already a javascript interpreter in inferno as part of the charon web browser. All I'd need to do is add a small set of host objects to interface with the OS. 

In this lab I haven't included all the host objects I'd want; not even a fraction. This is just the setup, the beginnings of a javascript tool.

Suggestions on what the host objects should be are welcome.

	% cat t1.js
	function f(n) {
		return n * 2;
	}
	
	var s;
	while((s = System.getline()))
		System.print(s + f(1));
	
	% echo a | js -f t1.js
	a
	2% 
