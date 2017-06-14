# NAME
lab 111 - wavloop
# NOTES
[WAV file format](http://www.sonicspot.com/guide/wavefiles.html) contains audio sample data and optionally meta-data that describe the offsets of sample loops and cue points. The loop offsets are used by sampler software to generate a continuous sound, and the cue points mark the point in the sample data where the sound fades away after the note has been released.

A WAV file "smpl" chunk will identify the  sample offset of the start and end of the loop in the sound data. Using wavplay.b as a starting point I tried to loop a sampled sound. 

My sample data comes from Virtual Organ software [GrandOrgue](http://sourceforge.net/projects/ourorgan/) and the [sample sets](http://sourceforge.net/p/ourorgan/samplesets/Sample%20Sets/) created for it. In this case I'm using the [Burea Funeral Chapel](http://sourceforge.net/p/ourorgan/samplesets/Burea_funeral/) sample set.

My first test was simply to treat the sample as-is and loop the sound using the given offsets. This did not give good results with a notable noise as the data from the end of the sample joined with the beginning. I realized nearing the end of writing this post that the mistake I made was treating the offsets as counts of bytes instead of samples. The documentation I was using said they were bytes. But the early mistake caused me to develop the following, which turned out useful. You can try out my first experiment yourself with this lab's code and the included sample.
	% wavloop -n -s 045-A.wav
The -s flag treats sample offsets as byte counts. The -n flag turns off finding the nearest zero.

Audacity has a feature where you can move the selection boundary to the nearest zero in the waveform. In the picture above that would be the beginning, middle, or end of the waveform. Using this feature creates a more seamless transition between the end and start of the loop. However, the sound samples can be any point along the curve and there are very few actual zeroes in the sample data. Instead I search for the crossing point of the y axis from negative to positive. The start and end samples must cross the zero-line going in the same direction. In the picture, the end of the graph is crossing the boundary in the upward direction and would join perfectly with the start or the curve forming a perfect loop. Play the sample without the -n flag to hear the difference.
	% wavloop -s 045-A.wav
This works in most cases, but because the sample is in stereo the left and right channel might not be heading in the same direction at the same time.

For the release cuepoint I follow a similar technique. I search for the zero crossing point where the data is rising. That will be where I jump to. But where I jump from could be anywhere in the sample data. So when the release event happens I also need to look for the nearest crossing point from where I am. This gives us the state transitions in the code for generating the sound data: START, LOOPING, RELEASING, RELEASE, and DONE.

For the final experiment I tried to use the begin and end markers in the wav file as sample counts instead of bytes. In a 16bit, 2 channel WAV file there are 4 bytes for each stereo sample. This ended up making the best sounding loops.
	% bind -a '#A' /dev
	% wavloop -n 045-A.wav
This is a lot of explanation for a little bit of code. I was hoping writing it out would help me figure out how to fix the looping to sound seamless in all cases, which it did, since I eventually tried the experiment of treating offsets as sample counts. But finding the nearest zero is still useful for jumping to the release cue point. The other way of making that join is by using a cross-fade, which I didn't try.

The next step will be to load in a complete sample set, at least for one windchest, and implement midiplay's Instrument interface to plugin to midiplay.