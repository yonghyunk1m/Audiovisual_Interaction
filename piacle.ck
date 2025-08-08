/*
██████╗ ██╗  █████╗   ██████╗ ██╗     ███████╗
██╔══██╗██║ ██╔══██╗ ██╔════╝ ██║     ██╔════╝
██████╔╝██║ ███████║ ██║      ██║     █████╗
██╔═══╝ ██║ ██╔══██║ ██║      ██║     ██╔══╝
██║     ██║ ██║  ██║ ╚██████╗ ███████╗███████╗
╚═╝     ╚═╝ ╚═╝  ╚═╝  ╚═════╝ ╚══════╝╚══════╝

Author: Yonghyun Kim (https://yonghyunk1m.com/)
Date: Summer 2025
*/

GWindow.fullscreen(); // Fullscreen

// === 1. Initialization ===

// examples

"midi/FantasieImpromptu.mid" => string midiFilePath;
2 => int track_num;

// "midi/BumbleBee.mid" => string midiFilePath;
// 1 => int track_num;


// Color Palette
@(0.8*0.6392, 0.6941, 2.5*0.9255) => vec3 light_purple;
@(0.8*0.5294, 0.5765, 2.5*0.5765) => vec3 dark_purple;
10*@(.9961, .9843, .2) => vec3 yellow;
12*@(0.8, 0.2, 0.2) => vec3 red;
@(0.6, 2.5*1.0, 2.5*0.8) => vec3 mint;

// Scene
GG.scene() @=> GScene @ scene;
scene.backgroundColor(light_purple);
scene.light().intensity(0);
scene.ambient(@(1, 1, 1));
Circle targetCircle --> scene;
targetCircle.color(red);
targetCircle.pos(@(0, 0, 0.01));
targetCircle.sca(2.5);

class BorderCircle extends GGen {
    GLines circle --> this;
    fun void init( int resolution, float radius, float startAngle, float endAngle ) {
        vec2 pos[resolution];
        (endAngle - startAngle) => float angleSpan;
        
        for( int i; i < resolution; i++ ) {
            i / (resolution - 1.0) => float progress;
            startAngle + angleSpan * progress => float currentAngle;
            
            radius * Math.cos(currentAngle) => pos[i].x;
            radius * Math.sin(currentAngle) => pos[i].y;
        }
        circle.positions( pos );
    }
    fun void color( vec3 c ) { circle.color( c ); }
    circle.width(.1);
}
class Circle extends GGen {
    GCircle circle --> this;
    fun void init( int resolution, float radius ) { circle.sca(2*radius); }
    fun void color( vec3 c ) { circle.color( c ); }
    fun void alpha( float a ) { circle.alpha( a ); }
}

BorderCircle boundaryCircle --> scene; 
3.0 => float BOUNDARY_RADIUS;

boundaryCircle.init(128, BOUNDARY_RADIUS, 1.25 * pi, -0.25 * pi);
boundaryCircle.color(dark_purple);
boundaryCircle.pos(@(0, 0, 0.05));

Circle previewCircle --> scene;
previewCircle.init(128, 0.5);
yellow => previewCircle.color;

8.0 => float BAR_WIDTH;
0.1 => float BAR_HEIGHT;
3.5 => float BAR_Y_POS;

GGen progressBarBG --> scene;
GPlane bgPlane --> progressBarBG;
progressBarBG.pos(@(0, BAR_Y_POS, 0));
bgPlane.sca(@(BAR_WIDTH, BAR_HEIGHT, 1.0));
bgPlane.color(dark_purple);

GText endText;
endText.text("End");
dark_purple => endText.color;
endText.pos(@(0, 0, 0.2));

// === 2. Object Pooling & Functions ===
class CompleteNote { int pitch; int velocity; dur duration; dur OnsetTime; }

127 => int minPitchInSong;
0 => int maxPitchInSong;
400::ms => dur BASE_NOTE_DURATION;
800::ms => dur BASE_TRAVEL_TIME;
300::ms => dur MIN_TRAVEL_TIME;
2000::ms => dur MAX_TRAVEL_TIME;
50::ms  => dur MIN_HOLD_TIME;
25::ms => dur CHORD_THRESHOLD;

1500 => int MAX_CIRCLES;
Circle noteCircles[MAX_CIRCLES];
int isCircleActive[MAX_CIRCLES];
for (int i; i < MAX_CIRCLES; i++) {
    noteCircles[i].init(128, 0.5);
    dark_purple => noteCircles[i].color;
    0 => isCircleActive[i];
}

1500 => int MAX_TRACES;
Circle traceCircles[MAX_TRACES];
0 => int traceCircleIndex;
for (int i; i < MAX_TRACES; i++) {  
    traceCircles[i].init(128, 0.3);
}

100 => int MAX_PREVIEWS;
Circle previewCircles[MAX_PREVIEWS];
for (int i; i < MAX_PREVIEWS; i++) {
    previewCircles[i].init(128, 0.5);
    yellow => previewCircles[i].color;
}

GPlane progressBlocks[];

fun vec3 getPitchColor(int pitch) {
    float colorProgress;
    if (minPitchInSong == maxPitchInSong) 0.5 => colorProgress;
    else Math.remap(pitch, minPitchInSong, maxPitchInSong, 0.0, 1.0) => colorProgress;
    
    return mint * (1 - colorProgress) + yellow * colorProgress;
}

fun void revealProgressBlock(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= progressBlocks.size()) return;
    
    processedNotes[noteIndex] @=> CompleteNote note;
    progressBlocks[noteIndex] @=> GPlane block;
    
    getPitchColor(note.pitch) @=> vec3 color;

    block.color(color);
}

fun void fadeAndDestroyTrace(Circle trace) {
    1::second => dur fadeTime;
    now => time startTime;
    
    while (now < startTime + fadeTime) {
        (now - startTime) / fadeTime => float progress;
        dark_purple * (1 - progress) + light_purple * progress @=> vec3 newColor;
        trace.color(newColor);
        GG.nextFrame() => now;
    }
    trace.detach();
}

NRev rev => dac;
0.1 => rev.mix;

@import "FluidSynth";
FluidSynth f => rev;
f => dac;
0.8 => f.gain;
f.open("soundfont/YDP-GrandPiano-20160804.sf2"); // Load your SoundFont


fun void animateAndDestroy(Circle c, int index, dur musicalDuration, int pitch, int velocity) {
    //<<< "Animating and destroying circle at index: ", index, " with pitch: ", pitch, " and velocity: ", velocity >>>;
    float colorProgress;
    if (minPitchInSong == maxPitchInSong) 0.5 => colorProgress; // 음이 하나뿐인 경우 중간 색상
    else Math.remap(pitch, minPitchInSong, maxPitchInSong, 0.0, 1.0) => colorProgress;
    mint * (1 - colorProgress) + yellow * colorProgress @=> vec3 noteColor;
    c.color(noteColor);
    c.sca(2.5*velocity/127.0);
    
    c.pos() @=> vec3 startPos; targetCircle.pos() @=> vec3 endPos; now => time startTime;
    BASE_TRAVEL_TIME * (musicalDuration / BASE_NOTE_DURATION) => dur calculatedTravelTime;
    (Math.max(MIN_TRAVEL_TIME / (1::ms), Math.min(MAX_TRAVEL_TIME / (1::ms), calculatedTravelTime / (1::ms)))) * (1::ms) => dur actualTravelTime;
    while (now < startTime + actualTravelTime) {
        (now - startTime) / actualTravelTime => float progress; 1 - Math.pow(1 - progress, 3) => float easeOutProgress; vec3 newPos; 
        (endPos - startPos) * easeOutProgress + startPos => newPos; c.pos(newPos); GG.nextFrame() => now; 
    }
    c.pos(endPos);
    musicalDuration - actualTravelTime => dur holdTime;
    if (holdTime < MIN_HOLD_TIME) MIN_HOLD_TIME => holdTime;
    if (holdTime > 0::ms) { holdTime => now; }
    
    500::ms => dur fadeOutTime;
    now => time fadeStartTime;
    while (now < fadeStartTime + fadeOutTime) {
        (now - fadeStartTime) / fadeOutTime => float progress;
        1.0 - progress => float alpha;
        c.alpha(alpha);
        GG.nextFrame() => now;
    }
    //0 => isCircleActive[index];
    c.detach();
}

fun void playNote(int key, int velocity, dur noteDuration) {
    f.noteOn(key, velocity);
    noteDuration => now;
    f.noteOff(key);
}

fun void triggerVisual(int key, int velocity, dur animationDuration) {
    for (int i; i < MAX_CIRCLES; i++) {
        if (!isCircleActive[i]) {
            float angle;
            if (minPitchInSong == maxPitchInSong) 1.25 * pi => angle;
            else Math.remap(key, minPitchInSong, maxPitchInSong, 1.25 * pi, -0.25 * pi) => angle;

            BOUNDARY_RADIUS * Math.cos(angle) => float startX;
            BOUNDARY_RADIUS * Math.sin(angle) => float startY;
            spork ~ fadeAndDestroyTrace(traceCircles[traceCircleIndex]);
            (traceCircleIndex + 1) % MAX_TRACES => traceCircleIndex;
            traceCircles[traceCircleIndex] @=> Circle newTrace;
            newTrace.pos(@(startX, startY, 0.005));
            newTrace.color(dark_purple);
            newTrace.sca(4.5*velocity/127.0);
            newTrace --> scene;
            1 => isCircleActive[i];
            noteCircles[i].pos(@(startX, startY, 0.1+(128-velocity)*0.0001));
            noteCircles[i].color(dark_purple);
            noteCircles[i] --> scene;
            spork ~ animateAndDestroy(noteCircles[i], i, animationDuration, key, velocity);
            break;
        }
    }
}

fun void showNextNotePreview(int startIndex) {
    for (int i; i < MAX_PREVIEWS; i++) { previewCircles[i].detach(); }
    if (startIndex >= processedNotes.size()) return;
    0 => int previewCount;
    processedNotes[startIndex] @=> CompleteNote firstNote;
    
    while(startIndex < processedNotes.size() && previewCount < MAX_PREVIEWS) {
        processedNotes[startIndex] @=> CompleteNote currentNote;
        previewCircles[previewCount] @=> Circle preview;
        
        getPitchColor(currentNote.pitch) @=> vec3 previewColor;
        preview.color(previewColor);

        float angle;
        if (minPitchInSong == maxPitchInSong) 1.25 * pi => angle;
        else Math.remap(currentNote.pitch, minPitchInSong, maxPitchInSong, 1.25 * pi, -0.25 * pi) => angle;
        BOUNDARY_RADIUS * Math.cos(angle) => float x;
        BOUNDARY_RADIUS * Math.sin(angle) => float y;
        preview.pos(@(x, y, 0.05));
        preview --> scene;
        previewCount++;
        
        if (startIndex + 1 < processedNotes.size()) {
            processedNotes[startIndex+1] @=> CompleteNote nextNote;
            if(nextNote.OnsetTime - firstNote.OnsetTime > CHORD_THRESHOLD) break;
        } else { break; }
        startIndex++;
    }
}

fun void pulseTargetCircle(int velocity) {
    targetCircle.sca() @=> vec3 originalScale;
    <<<velocity>>>;
    1.03 + velocity*0.003 => float pulseFactor;
    150::ms => dur pulseDuration;
    
    for (0 => float t; t < 1.0; 0.1 +=> t) {
        originalScale * (1.0 + (pulseFactor - 1.0) * Math.sin(t * pi)) @=> vec3 newScale;
        targetCircle.sca(newScale.x);
        pulseDuration / 10 => now;
    }
    targetCircle.sca(2.5);
}

// === 3. MIDI File Preprocessing ===
CompleteNote processedNotes[0];
class TimedEvent { MidiMsg msg; dur absoluteTime; }
MidiFileIn mfin;
if (mfin.open(midiFilePath)) {
    MidiMsg msg; 0 => int numEvents;
    while (mfin.read(msg, track_num)) { numEvents++; }
    mfin.rewind(track_num);
    TimedEvent timedEvents[numEvents];
    0::second => dur currentTime;
    for (int i; i < numEvents; i++) {
        TimedEvent te; new MidiMsg @=> te.msg; mfin.read(te.msg, track_num);
        currentTime + te.msg.when => currentTime;
        currentTime => te.absoluteTime;
        te @=> timedEvents[i];
    }
    TimedEvent noteOnEvents[0];
    for (int i; i < timedEvents.size(); i++) {
        if ((timedEvents[i].msg.data1 & 0xF0) == 0x90 && timedEvents[i].msg.data3 > 0) {
            noteOnEvents << timedEvents[i];
        }
    }
    for (int i; i < noteOnEvents.size(); i++) {
        CompleteNote cn;
        noteOnEvents[i].msg.data2 => cn.pitch;
        noteOnEvents[i].msg.data3 => cn.velocity;

        noteOnEvents[i].absoluteTime => cn.OnsetTime;

        if (i + 1 < noteOnEvents.size()) {
            noteOnEvents[i+1].absoluteTime - noteOnEvents[i].absoluteTime => cn.duration;
        } else { 250::ms => cn.duration; }
        if (cn.duration <= 0::ms) { 100::ms => cn.duration; }
        processedNotes << cn;
    }
    cherr <= "Pre-processing complete! " <= processedNotes.size() <= " notes are ready." <= IO.nl();

    if (processedNotes.size() > 0) {
        for (CompleteNote note : processedNotes) {
            if (note.pitch < minPitchInSong) note.pitch => minPitchInSong;
            if (note.pitch > maxPitchInSong) note.pitch => maxPitchInSong;
        }
        // cherr <= "Song pitch range: " <= minPitchInSong <= " - " <= maxPitchInSong <= IO.nl();
    }

        if (processedNotes.size() > 0) {
        BAR_WIDTH / processedNotes.size() => float blockWidth;
        new GPlane[processedNotes.size()] @=> progressBlocks;

        for (int i; i < progressBlocks.size(); i++) {
            new GPlane @=> progressBlocks[i];
            -BAR_WIDTH / 2.0 + blockWidth / 2.0 + i * blockWidth => float blockX;
            progressBlocks[i].pos(@(blockX, 0, 0.01));
            progressBlocks[i].sca(@(blockWidth, BAR_HEIGHT, 1.0));
            dark_purple => progressBlocks[i].color;
            progressBlocks[i] --> progressBarBG;
        }
    }

    //cherr <= "Press any arrow key to play." <= IO.nl(); // 키 안내 메시지 수정
} else { cherr <= "ERROR: Could not open MIDI file." <= IO.nl(); }

// === 4. Main Loop ===
GCamera camera;
camera --> GGen dolly --> scene;
camera.pos(@(0, 0.5, 10));
scene.camera(camera);
camera.orthographic();

0 => int noteIndex;
0 => int key_pressed;

showNextNotePreview(noteIndex);

while(true) {
    GWindow.keysDown() @=> int pressedKeys[];
    if (pressedKeys.size() > 0 && !key_pressed) {
        1 => key_pressed;

        if (noteIndex < processedNotes.size()) {
            processedNotes[noteIndex] @=> CompleteNote currentNote;
            spork ~ playNote(currentNote.pitch, currentNote.velocity, currentNote.duration);
            spork ~ pulseTargetCircle(currentNote.velocity);
            triggerVisual(currentNote.pitch, currentNote.velocity, currentNote.duration);
            revealProgressBlock(noteIndex);

            while (noteIndex + 1 < processedNotes.size()) {
                processedNotes[noteIndex + 1] @=> CompleteNote nextNote;
                nextNote.OnsetTime - currentNote.OnsetTime => dur timeDiff;

                if (timeDiff <= CHORD_THRESHOLD) {
                    noteIndex++;
                    processedNotes[noteIndex] @=> currentNote;
                    
                    spork ~ playNote(currentNote.pitch, currentNote.velocity, currentNote.duration);
                    triggerVisual(currentNote.pitch, currentNote.velocity, currentNote.duration);
                    revealProgressBlock(noteIndex);
                }
                else {break;}
            }
            
            noteIndex++;
            showNextNotePreview(noteIndex);
        } else {
            cherr <= "End of sequence." <= IO.nl();
            endText --> scene;
        }
    }
    if (pressedKeys.size() == 0) { 0 => key_pressed; }
    GG.nextFrame() => now;
}
