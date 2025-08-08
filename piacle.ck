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
//"midi/BumbleBee.mid" => string midiFilePath;
"midi/FantasieImpromptu.mid" => string midiFilePath;
//"midi/GT_MIDI-Unprocessed_01_R1_2006_01-09_ORIG_MID--AUDIO_01_R1_2006_02_Track02_wav.midi" => string midiFilePath;
//"midi/2024-02-17_21-37-57.mid" => string midiFilePath;
1 => int track_num;//_RH;
//2 => int track_num_LH;

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
    // init 함수가 시작/끝 각도를 받도록 수정
    fun void init( int resolution, float radius, float startAngle, float endAngle ) {
        vec2 pos[resolution];
        // 각도 구간 전체 크기
        (endAngle - startAngle) => float angleSpan;
        
        for( int i; i < resolution; i++ ) {
            // 현재 진행률 (0.0 ~ 1.0)
            i / (resolution - 1.0) => float progress;
            // 시작 각도부터 끝 각도까지 보간
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
// 시작 각도와 끝 각도를 전달하여 호(arc)를 생성
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

// GGen progressBarFill --> scene;
// GPlane fillPlane --> progressBarFill;
// fillPlane.sca(@(0, BAR_HEIGHT, 1.0)); // 처음엔 너비 0
// fillPlane.color(mint);
// progressBarFill의 위치는 updateProgressBar 함수에서 계속 업데이트됨

// === 2. 오브젝트 풀링 및 기능 함수들 ===
class CompleteNote { int pitch; int velocity; dur duration; dur OnsetTime; }

127 => int minPitchInSong;
0 => int maxPitchInSong;

// --- 속도 제어 상수 ---
400::ms => dur BASE_NOTE_DURATION;
800::ms => dur BASE_TRAVEL_TIME;
300::ms => dur MIN_TRAVEL_TIME;
2000::ms => dur MAX_TRAVEL_TIME;
50::ms  => dur MIN_HOLD_TIME;
25::ms => dur CHORD_THRESHOLD;

// --- 그래픽 오브젝트 풀링 ---
2000 => int MAX_CIRCLES;
Circle noteCircles[MAX_CIRCLES];
int isCircleActive[MAX_CIRCLES];
for (int i; i < MAX_CIRCLES; i++) {
    noteCircles[i].init(128, 0.5);
    dark_purple => noteCircles[i].color;
    0 => isCircleActive[i];
}

2000 => int MAX_TRACES; // 동시에 화면에 존재할 최대 흔적 수
Circle traceCircles[MAX_TRACES];
0 => int traceCircleIndex; // 다음에 사용할 흔적 원의 인덱스
for (int i; i < MAX_TRACES; i++) {  
    traceCircles[i].init(128, 0.3); // 흔적은 조금 작게 설정
}

2000 => int MAX_PREVIEWS; // 동시에 표시할 수 있는 최대 미리보기 원의 수
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
    
    // 민트색(낮음)과 노란색(높음) 사이를 보간
    return mint * (1 - colorProgress) + yellow * colorProgress;
}

// fun void updateProgressBar(int currentIndex, int totalNotes) {
//     if (totalNotes <= 1) return;
    
//     // 1. 진행률 계산
//     (currentIndex-1) / (totalNotes - 1.0) => float progress;
    
//     // 2. 현재 색상 계산
//     processedNotes[currentIndex-1].pitch => int currentPitch;
//     getPitchColor(currentPitch) @=> vec3 fillColor;
//     fillPlane.color(fillColor);
    
//     // 3. 채워지는 바의 너비와 위치 계산
//     BAR_WIDTH * progress => float fillWidth;
//     -BAR_WIDTH / 2.0 + fillWidth / 2.0 => float fillX;
    
//     // 4. 프로그레스 바 위치 업데이트
//     progressBarFill.pos(@(fillX, BAR_Y_POS, 0.01));
    
//     // 5. 프로그레스 바 스케일(너비) 업데이트 (올바른 방식)
//     fillPlane.sca() @=> vec3 currentScale; // 현재 스케일(vec3)을 가져옴
//     fillWidth => currentScale.x;          // x값만 새로운 너비로 수정
//     fillPlane.sca(currentScale);           // 수정된 vec3 전체를 다시 적용
// }

fun void revealProgressBlock(int noteIndex) {
    if (noteIndex < 0 || noteIndex >= progressBlocks.size()) return;
    
    // 해당 인덱스의 노트 정보와 블록을 가져옴
    processedNotes[noteIndex] @=> CompleteNote note;
    progressBlocks[noteIndex] @=> GPlane block;
    
    // 음높이에 맞는 색상을 계산하여 블록에 적용
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
f.open("soundfont/YDP-GrandPiano-20160804.sf2");


// === 'animateAndDestroy' 함수 수정됨: 동적 음역대 사용 ===
fun void animateAndDestroy(Circle c, int index, dur musicalDuration, int pitch, int velocity) {
    <<< "Animating and destroying circle at index: ", index, " with pitch: ", pitch, " and velocity: ", velocity >>>;
    // 1. 음높이에 따라 민트색과 노란색을 동적 음역대 기준으로 보간
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
        1.0 - progress => float alpha; // 알파값 (1 -> 0)
        c.alpha(alpha);
        GG.nextFrame() => now;
    }
    //0 => isCircleActive[index];
    //<<<"Detaching">>>;
    c.detach(); // ★★★ 버그 수정 ★★★
}

// FluidSynth를 사용하도록 완전히 새로 작성된 playNote 함수
fun void playNote(int key, int velocity, dur noteDuration) {
    // FluidSynth에 Note On 신호 전송 (음높이, 세기)
    f.noteOn(key, velocity);
    // 음악적 길이만큼 기다림
    noteDuration => now;
    // FluidSynth에 Note Off 신호 전송
    f.noteOff(key);
}

fun void triggerVisual(int key, int velocity, dur animationDuration) {
    for (int i; i < MAX_CIRCLES; i++) {
        if (!isCircleActive[i]) {
            float angle;
            if (minPitchInSong == maxPitchInSong) 1.25 * pi => angle; // 음이 하나뿐인 경우 기본 위치
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

// fun void showNextNotePreview(int startIndex) {
//     for (int i; i < MAX_PREVIEWS; i++) { previewCircles[i].detach(); }
//     if (startIndex >= processedNotes.size()) return;
//     0 => int previewCount;
    
//     // 다음 연주 블록 (단일음 또는 화음) 전체를 미리 보여줌
//     while(startIndex < processedNotes.size() && previewCount < MAX_PREVIEWS) {
//         processedNotes[startIndex] @=> CompleteNote currentNote;
        
//         // 미리보기 원 표시
//         previewCircles[previewCount] @=> Circle preview;
//         float angle;
//         if (minPitchInSong == maxPitchInSong) 1.25 * pi => angle;
//         else Math.remap(currentNote.pitch, minPitchInSong, maxPitchInSong, 1.25 * pi, -0.25 * pi) => angle;
//         BOUNDARY_RADIUS * Math.cos(angle) => float x;
//         BOUNDARY_RADIUS * Math.sin(angle) => float y;
//         preview.pos(@(x, y, 0.05));
//         preview --> scene;
//         previewCount++;
        
//         // 다음 노트가 화음의 일부가 아니면 루프 종료
//         if (startIndex + 1 < processedNotes.size()) {
//             processedNotes[startIndex+1] @=> CompleteNote nextNote;
//             if(nextNote.OnsetTime - currentNote.OnsetTime > CHORD_THRESHOLD) break;
//         } else {
//             break;
//         }
//         startIndex++;
//     }
// }

// fun void showNextNotePreview(int nextNoteIndex) {
//     // 다음에 재생할 노트가 있는지 확인
//     if (nextNoteIndex < processedNotes.size()) {
//         // 다음 노트의 음높이를 가져옴
//         processedNotes[nextNoteIndex].pitch => int nextPitch;
        
//         // 위치 계산
//         Math.remap(nextPitch, 21, 108, 1.25 * pi, -0.25 * pi) => float angle;
//         BOUNDARY_RADIUS * Math.cos(angle) => float nextX;
//         BOUNDARY_RADIUS * Math.sin(angle) => float nextY;
        
//         // 미리보기 원을 해당 위치로 이동시키고 씬에 다시 붙임
//         previewCircle.pos(@(nextX, nextY, 0.5)); // 다른 원과 겹치지 않게 z 살짝 뒤로
//         previewCircle --> scene;
//     } else {
//         // 더 이상 노트가 없으면 미리보기 원을 숨김
//         previewCircle.detach();
//     }
// }

fun void showNextNotePreview(int startIndex) {
    // for (int i; i < MAX_PREVIEWS; i++) { previewCircles[i].detach(); }
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

// === 3. MIDI 파일 전처리 ===
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
        cherr <= "Song pitch range: " <= minPitchInSong <= " - " <= maxPitchInSong <= IO.nl();
    }

        if (processedNotes.size() > 0) {
        // 블록 하나당 너비 계산
        BAR_WIDTH / processedNotes.size() => float blockWidth;
        // 배열 크기 재설정
        new GPlane[processedNotes.size()] @=> progressBlocks;

        for (int i; i < progressBlocks.size(); i++) {
            new GPlane @=> progressBlocks[i];
            // 각 블록의 위치와 크기 설정
            -BAR_WIDTH / 2.0 + blockWidth / 2.0 + i * blockWidth => float blockX;
            progressBlocks[i].pos(@(blockX, 0, 0.01));
            progressBlocks[i].sca(@(blockWidth, BAR_HEIGHT, 1.0));
            // 처음에는 배경색과 동일하게 설정하여 보이지 않게 함
            dark_purple => progressBlocks[i].color;
            // 프로그레스 바 배경의 자식으로 붙임
            progressBlocks[i] --> progressBarBG;
        }
    }

    cherr <= "Press any arrow key to play." <= IO.nl(); // 키 안내 메시지 수정
} else { cherr <= "ERROR: Could not open MIDI file." <= IO.nl(); }

// === 4. 카메라 및 메인 루프 (화음 처리 로직으로 수정) ===
GCamera camera;
camera --> GGen dolly --> scene;
camera.pos(@(0, 0.5, 10));
scene.camera(camera);
camera.orthographic();

0 => int noteIndex;
0 => int key_pressed;

//showNextNotePreview(noteIndex);

while(true) {
    GWindow.keysDown() @=> int pressedKeys[];
    if (pressedKeys.size() > 0 && !key_pressed) {
        1 => key_pressed;

        // 연주할 노트가 남아있는지 확인
        if (noteIndex < processedNotes.size()) {
            // --- 1. 첫 노트 재생 ---
            processedNotes[noteIndex] @=> CompleteNote currentNote;
            spork ~ playNote(currentNote.pitch, currentNote.velocity, currentNote.duration);
            triggerVisual(currentNote.pitch, currentNote.velocity, currentNote.duration);
            revealProgressBlock(noteIndex);

            // --- 2. 다음 노트와의 시간 간격 확인 및 동시 재생 루프 ---
            while (noteIndex + 1 < processedNotes.size()) {
                // 다음 노트 가져오기
                processedNotes[noteIndex + 1] @=> CompleteNote nextNote;
                
                // 현재 노트와 다음 노트의 시작 시간 차이 계산
                nextNote.OnsetTime - currentNote.OnsetTime => dur timeDiff;
                
                // 시간 차이가 25ms 이하이면, 다음 노트도 함께 재생
                if (timeDiff <= CHORD_THRESHOLD) {
                    noteIndex++; // 인덱스를 다음 노트로 이동
                    processedNotes[noteIndex] @=> currentNote; // currentNote를 다음 노트로 업데이트
                    
                    //cherr <= "Chord note detected! Playing simultaneously." <= IO.nl();
                    spork ~ playNote(currentNote.pitch, currentNote.velocity, currentNote.duration);
                    triggerVisual(currentNote.pitch, currentNote.velocity, currentNote.duration);
                    revealProgressBlock(noteIndex);
                }
                // 시간 차이가 크면 루프 탈출
                else {break;}
            }
            
            // --- 3. 다음 연주를 위해 인덱스 최종 증가 ---
            noteIndex++;
            //revealProgressBlock(noteIndex); // ★★★ 블록 보이기 호출 ★★★
            //updateProgressBar(noteIndex, processedNotes.size());
            //showNextNotePreview(noteIndex);
        } else {
            cherr <= "End of sequence." <= IO.nl();
        }
    }
    if (pressedKeys.size() == 0) { 0 => key_pressed; }
    GG.nextFrame() => now;
}
