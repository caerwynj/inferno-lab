#NAME
lab 107 - midiplay
#NOTES
Midiplay plays back MIDI files. It uses the synthesizer I described in lab 62 and the MIDI module from lab 73. The command takes only one argument, the path to the midi file. I've included one in the lab to demonstrate. Bind the audio device before using it.

	% bind -a '#A' /dev
	% midiplay invent15.mid

The synthesizer has 16 note polyphony. It uses three oscillators, one at the pitch, one at half pitch, one at double pitch. There is also a filter, two delays and a vibrato. 

The sample rate is 8000hz and there is one mono channel (MIDI channel events are ignored). It performs well enough to work on my laptop without JIT turned on. All the synthesizer parameters can only be tweaked from inside the code at the moment.
