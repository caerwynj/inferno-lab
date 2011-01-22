implement Treemap;
include "sys.m";
	sys: Sys;
	print: import sys;
include "draw.m";
include "math.m";
	math: Math;
	sqrt, Infinity, fmax: import math;
include "treemap.m";

init()
{
	sys = load Sys Sys->PATH;
	math = load Math Math->PATH;
}

Rect.distance(r: self Rect, rr: Rect): real
{
	return sqrt((rr.x-r.x)**2 +(rr.y-r.y)**2 +(rr.w-r.w)**2 +(rr.h-r.h)**2);
}

Rect.aspect(r: self Rect): real
{
	return math->fmax(r.w/r.h, r.h/r.w);
}

sum(items: array of ref Item): real
{
	sum := 0.0;
	for(i:=0; i<len items; i++)
		sum += items[i].size;
	return sum;
}

slice(items: array of ref Item, bounds: Rect, orient: int, order: int)
{
	total := sum(items);
	if(0)
		sys->print("total %d %g, bounds %g %g %g %g\n", 
			len items, total, bounds.x, bounds.y, bounds.w, bounds.h);
	a := 0.0;
	vertical := 0;
	if(orient==VERTICAL)
		vertical = 1;
	for(i:=0; i<len items; i++){
		r := Rect(0.0,0.0,1.0,1.0);
		b := items[i].size/total;
		if(vertical){
			r.x = bounds.x;
			r.w = bounds.w;
			if(order == ASCENDING)
				r.y = bounds.y+bounds.h*a;
			else
				r.y = bounds.y+bounds.h*(1.0-a-b);
			r.h=bounds.h*b;
		}else{
			if (order==ASCENDING)
				r.x=bounds.x+bounds.w*a;
			else
				r.x=bounds.x+bounds.w*(1.0-a-b);
			r.w=bounds.w*b;
			r.y=bounds.y;
			r.h=bounds.h;
		}
		items[i].bounds = r;
		a += b;
	}
}

sliceBest(items: array of ref Item, bounds: Rect)
{
	h:= VERTICAL;
	if(bounds.w>bounds.h)
		h= HORIZONTAL;
	slice(items, bounds, h, ASCENDING);
}

square(items: array of ref Item, bounds: Rect)
{
	mergesort(items, array[len items] of ref Item);
	_square(items, bounds);
}

_square(items: array of ref Item, bounds: Rect)
{
	if(len items == 0)	
		return;
	if (len items <= 2){
		sliceBest(items, bounds);
		return;
	}

	start:=0;
	end:=len items;
	mid:=0;
	x:=bounds.x;
	y:=bounds.y;
	w:=bounds.w;
	h:=bounds.h;

	total:=sum(items);
	a:=items[0].size/total;
	b:=a;
	if(0)
		sys->print("square  %d %g, bounds %g %g %g %g\n", 
			len items, total, bounds.x, bounds.y, bounds.w, bounds.h);

	if (w<h){
	# height/width
		while (mid<end){
			aspect:=normAspect(h,w,a,b);
			q:=items[mid].size/total;
			if (normAspect(h,w,a,b+q)>aspect) 
				break;
			mid++;
			b+=q;
		}
		sliceBest(items[start:mid+1], Rect(x,y,w,h*b));
		_square(items[mid+1:end], Rect(x,y+h*b,w,h*(1.0-b)));
	}else{
		# width/height
		while (mid<end){
			aspect:=normAspect(w,h,a,b);
			q:=items[mid].size/total;
			if (normAspect(w,h,a,b+q)>aspect)
				break;
			mid++;
			b+=q;
		}
		sliceBest(items[start:mid+1], Rect(x,y,w*b,h));
		_square(items[mid+1:end], Rect(x+w*b,y,w*(1.0-b),h));
	}
}

aspect(large, small, a, b: real):real
{
	return (large*b)/(small*a/b);
}

normAspect(large, small, a, b: real):real
{
	x := aspect(large, small, a, b);
	if(x<1.0)
		return 1.0/x;
	return x;
}

btree(items: array of ref Item, bounds: Rect, vertical: int)
{
	if(len items == 0)
		return;
	if(len items == 1){
		items[0].bounds = bounds;
		return;
	}
	mid := len items/2;
	total := sum(items);
	first := sum(items[0:mid]);
	a := first/total;
	x := bounds.x;
	y := bounds.y;
	w := bounds.w;
	h := bounds.h;
	if(vertical){
		b1 := Rect(x,y,w*a,h);
		b2 := Rect(x+w*a,y,w*(1.0-a),h);
		btree(items[0:mid], b1, !vertical);
		btree(items[mid:], b2, !vertical);
	}else{
		b1 := Rect(x,y,w,h*a);
		b2 := Rect(x,y+h*a,w,h*(1.0-a));
		btree(items[0:mid], b1, !vertical);
		btree(items[mid:], b2, !vertical);
	}
}

lookahead := 1;

strip(items: array of ref Item, bounds: Rect)
{
	layoutbox := bounds;
	total := sum(items);

	area := layoutbox.w * layoutbox.h;
	scaleFactor := sqrt(area/total);

	finishedIndex := 0;
	numItems := 0;
	prevAR := 0.0;
	ar := 0.0;
	height := 0.0;
	yoffset := 0.0;
	box := layoutbox;
	box.x /= scaleFactor;
	box.y /= scaleFactor;
	box.w /= scaleFactor;
	box.h /= scaleFactor;

	while(finishedIndex < len items){
		numItems = layout_strip(items[finishedIndex:], box);

		if(lookahead){
			if((finishedIndex + numItems) < len items){
				numItems2 := 0;
				ar2a := 0.0;
				ar2b := 0.0;
				
				numItems2 = layout_strip(items[finishedIndex+numItems:], box);
				ar2a = avg_aspect(items[finishedIndex:finishedIndex+numItems+numItems2]);
				horiz_box(items[finishedIndex:finishedIndex+numItems+numItems2], box);
				ar2b = avg_aspect(items[finishedIndex:finishedIndex+numItems+numItems2]);
				if(ar2b<ar2a){
					numItems += numItems2;
				}else{
					horiz_box(items[finishedIndex:finishedIndex+numItems], box);
				}
			}
		}		
		for(i:=finishedIndex;i<(finishedIndex+numItems);i++){
			items[i].bounds.y += yoffset;
		}
		height = items[finishedIndex].bounds.h;
		yoffset += height;
		box.y += height;
		box.h -= height;

		finishedIndex += numItems;
	}
	for(i:=0;i<len items;i++){
		rect := items[i].bounds;
		rect.x *= scaleFactor;
		rect.y *= scaleFactor;
		rect.w *= scaleFactor;
		rect.h *= scaleFactor;

		rect.x += bounds.x;
		rect.y += bounds.y;
		items[i].bounds = rect;
	}
}

layout_strip(items: array of ref Item, box: Rect): int
{
	numItems := 0;
	ar := Infinity;
	prevAR := 0.0;
	height := 0.0;
	do{
		prevAR  = ar;
		numItems++;
		height = horiz_box(items[0:numItems], box);
		ar = avg_aspect(items[0:numItems]);
	} while((ar < prevAR) && (numItems < len items));
	if(ar >= prevAR){
		numItems--;
		height = horiz_box(items[0:numItems], box);
		ar = avg_aspect(items[0:numItems]);
	}
	return numItems;
}

horiz_box(items: array of ref Item, box: Rect): real
{
	total := sum(items);
	height := total / box.w;
	width := 0.0;
	x := 0.0;

	for(i:=0;i<len items;i++){
		width = items[i].size/height;
		items[i].bounds = Rect(x, 0.0, width, height);
		x += width;
	}
	return height;
}

avg_aspect(items: array of ref Item): real
{
	tar := 0.0;

	if(len items == 0)
		return 0.0;
	for(i:=0;i<len items;i++){
		tar += items[i].bounds.aspect();
	}
	tar /= real len items;
	return tar;
}

ptinrect(r: Rect, x, y: real): int
{
	return x >= r.x && x < r.x+r.w && y >= r.y && y < r.y+r.h;
}

getitem(root: ref Item, x, y: real): ref Item
{
	if(root.children == nil)
		return root;
	for(g:=root.children; g!=nil; g= tl g)
		if(ptinrect((hd g).bounds, x, y))
			return getitem(hd g, x, y);
	return nil;
}

getpath(root: ref Item, x, y: real): list of ref Item
{
	if(root.children == nil)
		return root :: nil;
	for(g:=root.children; g!=nil; g= tl g)
		if(ptinrect((hd g).bounds, x, y))
			return root :: getpath(hd g, x, y);
	return root :: nil;
}

Item.enter(dir: self ref Item, f: ref Item)
{
	f.parent = dir;
	for(g:=dir.children; g!=nil; g = tl g){
		if((hd g).name == f.name){
			(hd g).size = f.size;
			return;
		}
	}
	dir.children = f :: dir.children;
}

Item.find(f: self ref Item, name: string): ref Item
{
	for(g := f.children; g != nil; g = tl g)
		if((hd g).name == name)
			return hd g;
	return nil;
}


mergesort(a, b: array of ref Item)
{
	r := len a;
	if (r > 1) {
		m := (r-1)/2 + 1;
		mergesort(a[0:m], b[0:m]);
		mergesort(a[m:], b[m:]);
		b[0:] = a;
		for ((i, j, k) := (0, m, 0); i < m && j < r; k++) {
			if(b[i].size >b[j].size)
				a[k] = b[j++];
			else
				a[k] = b[i++];
		}
		if (i < m)
			a[k:] = b[i:m];
		else if (j < r)
			a[k:] = b[j:r];
	}
}
