import ddf.minim.*; 
import ddf.minim.analysis.*;
import ddf.minim.ugens.*;
import processing.serial.*;

Minim minim;
AudioOutput out;
Waveform currentWaveform; // 音色格納用変数
String frequency; // 周波数格納変数
Serial myPort;  // シリアル通信

FFT fft;
boolean isSoundPlaying = false;      // 音が出ているかのフラグ
String currentPitchText = "-";       // 音階（ドレミ）の文字
float currentFrequency = 0.0;        // 周波数の数字
PFont jpFont;                        // 日本語を出すためのフォント

// Arduinoから送られた値を格納する変数
float bpm = 0.0f;  // BPM
String note = "";  // 音階
float noteLength = 0.0f; // 長さ

// 録音用
AudioRecorder recorder;
boolean isRecording = false;

float topMargin = 50;

// 音色を変更するためにInstrument インタフェースを実装 
class HackInstrument implements Instrument {
  
  Oscil[] wave = new Oscil[3]; // 3つの音信号の波形
  float[] detune = {-0.0f, 0.0f, 0.0f}; // デチューンのそれぞれのズレ
  Oscil[] lfoVibrato = new Oscil[3]; // LFO(ビブラート用)の波形
  ADSR[] vibratoAdsr = new ADSR[3]; // LFO(ビブラート用)のエンベロープを格納する変数
  Summer[] freqSummer = new Summer[3]; // 周波数を合成する変数
  Constant[] baseFreq = new Constant[3]; // 基本となる周波数
  Summer waveSummer; // 3つの波形を合成する変数
  
  Noise pinkNoise; // ピンク変数
  MoogFilter moogFilter; // モーグフィルタ変数
  ADSR adsr; // エンベロープ変数
  Delay delay; // ディレイ変数
  
  
  HackInstrument( float frequency, float maxAmp, Waveform wf ) { 
    // 1.音信号の作成とデチューンの適用、ビブラートの適用を行い合成
    
    waveSummer = new Summer();
   
    for (int i = 0; i < 3; i++) {
      freqSummer[i] = new Summer();
      // LFO(ビブラート用)を作成(周波数, 振幅, 音色)
      lfoVibrato[i] = new Oscil(5.5f+0.05*i, 2.0f, Waves.SINE);
      // LFO(ビブラート用)のエンベロープの設定 (最大振幅, A, D, S, R)
      vibratoAdsr[i] = new ADSR(2.0, 1.0, 0.0, 0.6, 0.01);
      lfoVibrato[i].patch( vibratoAdsr[i] );
      // 基本の周波数を設定
      baseFreq[i] = new Constant(frequency + detune[i]);
      // 基本の周波数を追加
      baseFreq[i].patch( freqSummer[i] );
      // ±2Hzの揺れを追加
      vibratoAdsr[i].patch( freqSummer[i] );
      
      /* if(i==1){
      // 音信号を作成(周波数, 振幅0~1, 音色)
      wave[i] = new Oscil(frequency, 0.4f, wf);
      }else{
      wave[i] = new Oscil(frequency, 0.1f, wf);
      } */
      float baseAmp;
      
      if(i==1){
        baseAmp = 0.4f;
      }else{
        baseAmp = 0.1f;
      }
      
      wave[i] = new Oscil(frequency, baseAmp, wf);
      
      // 波形の開始地点をランダムに設定
      wave[i].setPhase( random(0, 1) );
      // LFO(ビブラート用)を各音信号の周波数に代入
      freqSummer[i].patch( wave[i].frequency ); 
      // 各音信号をSummerへ合成
      wave[i].patch( waveSummer );
    }
    
    // 2.ノイズを追加
    
    // ピンクノイズを作成(振幅0~1, ノイズの種類)
    pinkNoise = new Noise(0.015, Noise.Tint.PINK);
    pinkNoise.patch( waveSummer );
    
    // 3.モーグフィルタ(ローパスフィルタ)の追加
    
    // フィルタを作成(カットオフ周波数, レゾナンス0~1, フィルタの種類)
    moogFilter = new MoogFilter(3400.0f, 0.12f, MoogFilter.Type.LP);
    waveSummer.patch( moogFilter );
        
    // 4.ディレイの追加
    
    // ディレイの作成(遅れる時間, 音の大きさ0~1, 繰り返すか, 元の音を出力に混ぜるか)
    delay = new Delay( 0.001f, 0.08f, true, true );
    moogFilter.patch( delay );
    
    // 5.エンベロープの制御
    
    // エンベロープの設定(最大振幅, A, D, S, R)
    adsr = new ADSR(maxAmp, 0.11, 0.5, 0.8, 0.10);
    delay.patch( adsr );
    
  }
  
  // コールバック関数:再生開始
  void noteOn(float duration)
  { 
    for (int i = 0; i < 3; i++) {
      // 3波形のビブラートのエンベロープの開始
      vibratoAdsr[i].noteOn();
    }
    // 振幅のエンベロープ(ADSR)のADSの開始
    adsr.noteOn(); 
    // 音の再生
    adsr.patch( out );
   }
   
   // コールバック関数:再生停止 
  void noteOff()
  {  
    for (int i = 0; i < 3; i++) {
      // 3波形のビブラートのエンベロープの停止
      vibratoAdsr[i].noteOff();
    }
    // 振幅のエンベロープの停止
    adsr.noteOff();
    // Rが終わり次第再生の停止
    adsr.unpatchAfterRelease( out );
   
  }
}

void setup() 
{
  fullScreen();
  printArray(Serial.list());  // シリアルポートのリストを表示
  myPort = new Serial(this, Serial.list()[2], 115200);  // シリアルポートと通信速度を指定
  myPort.bufferUntil('\n');  // 改行されたらSerialEvent関数を実行
  
  // minimのインスタンスを用意
  minim = new Minim(this);
  // minimのgetLineOutメソッドを呼び出し，AudioOutputオブジェクトを受け取る 
  out = minim.getLineOut();
  // テンポの初期設定(BPM=120)
  out.setTempo( 120 );
  //音階の初期値
  frequency = "A4";
  // 音色の初期値
  currentWaveform = WavetableGenerator.gen10(
      4096, // サンプルサイズ(2の倍数で)
      // 各倍音の振幅値
      new float[] { 0.447f, 1.000f, 0.355f, 0.158f,
                   0.224f, 0.089f, 0.056f,
                   0.035f, 0.013f, 0.013f }  //フルート
      );
      
  recorder = minim.createRecorder(out, "my_violin.wav"); // 録音用
  

  fft = new FFT(out.bufferSize(), out.sampleRate()); // 音のFFTする装置を用意

  // 日本語の文字を用意
  String[] fontList = PFont.list();
  String selectedFont = "SansSerif";
  for (String f : fontList) {
    if (f.equals("Hiragino Kaku Gothic ProN W3") || f.equals("ヒラギノ角ゴ ProN") ||
        f.equals("Meiryo") || f.equals("MS Gothic") || f.equals("Osaka")) {
      selectedFont = f;
      break;
    }
  }
  jpFont = createFont(selectedFont, 24, true);
  textFont(jpFont);
}

void playSong() {
  // 再生を停止
  out.pauseNotes();
   // 音を追加(開始時刻，音の長さ，Instrumentのインスタンス)
   out.playNote(0.0f, noteLength,
     new HackInstrument(Frequency.ofPitch( note ).asHz(),
       0.5f, currentWaveform));
  // 再生
  out.resumeNotes(); 
}

void draw() {
  background(30);

  // 1. 音の解析とドレミの計算
  analyzeAudio();

  // 2. 描画処理（左半分に波形とスペクトルを描く）
  drawDrumPlots();       
  drawInfoPanel(); // （右半分にBPMやドレミを描く）
}

void serialEvent(Serial p) {
  // 文字列を改行（'\n'）まで読み込む
  String inString = p.readStringUntil('\n');
  
  if (inString != null) {
    // 余計な空白を削除
    inString = trim(inString);
    
    // カンマ「,」でデータを3つに分割
    String[] list = split(inString, ',');
    
    // 3つのデータが揃っていた場合
    if (list.length == 3) {
      // それぞれの変数にデータを格納
      bpm = float(list[0]);  // BPM
      note = list[1];  // 音階
      noteLength = float(list[2]);  // 長さ
      
      out.setTempo( bpm );  //BPMの更新
      playSong();  // 音の再生
      println("BPM:" + bpm + " 音階:" + note + " 長さ:" + noteLength);
    }
  }
}

void keyPressed() { 
  switch (key)
  {
  case 'r': // 'r'キーで録音開始/停止
      if (recorder.isRecording()) {
        recorder.endRecord();
        recorder.save(); // ファイルとして書き出し
        isRecording = false;
        println("録音終了: ファイルを保存しました");
      } else {
        recorder.beginRecord();
        isRecording = true;
        println("録音開始...");
      }
    break;
  default: 
    break;
  } 
}

// ★一番下にこの関数を丸ごと貼り付けます
String hzToPitchName(float hz) {
  if (hz <= 0) return "-";
  
  float noteNumber = 12 * (log(hz / 440.0) / log(2.0)) + 69;
  int roundedNote = round(noteNumber);
  
  String[] noteNames = {"ド", "ド#", "レ", "レ#", "ミ", "ファ", "ファ#", "ソ", "ソ#", "ラ", "ラ#", "シ"};
  
  int noteIndex = (roundedNote % 12 + 12) % 12;
  int octave = (roundedNote / 12) - 1;
  
  return noteNames[noteIndex] + " (" + octave + ")";
}

void analyzeAudio() {
  fft.forward(out.mix);
  
  float maxAmp = 0;
  int maxBin = -1;
  int maxDisplayBins = min(fft.specSize(), 500);

  for (int i = 0; i < maxDisplayBins; i++) {
    float amp = fft.getBand(i);
    if (amp > maxAmp) {
      maxAmp = amp;
      maxBin = i;
    }
  }

  if (maxAmp > 0.1 && maxBin > 0) {
    isSoundPlaying = true;
    currentFrequency = maxBin * ((float)out.sampleRate() / out.bufferSize());
    currentPitchText = hzToPitchName(currentFrequency);
  } else {
    isSoundPlaying = false;
    currentFrequency = 0.0;
    currentPitchText = "-";
  }
}

void drawDrumPlots() {
  // ★画面レイアウトの計算のために、全画面のサイズをここでセットします
  int plotWidth = width / 2;
  float drawHeight = height - (topMargin * 2);
  
  float halfHeight = drawHeight / 2;
  float topY = topMargin;
  float bottomY = topMargin + halfHeight;     
  float areaBottomY = topMargin + drawHeight; 

  // 【上半分】波形の描画（黄色いライン）
  stroke(255, 200, 0); 
  strokeWeight(2);
  noFill();
  beginShape();
  for (int i = 0; i < plotWidth; i++) {
    // ★ player.bufferSize() だった場所を out.bufferSize() に変更
    int idx = int(map(i, 0, plotWidth, 0, out.bufferSize()));
    // ★ player.mix だった場所を out.mix に変更
    float sample = out.mix.get(idx);

    float x = i;
    float y = (topY + halfHeight / 2) + sample * (halfHeight / 2) * 0.9;
    vertex(x, y);
  }
  endShape();

  // 【区切り線】左上と左下を分ける線
  stroke(100);
  strokeWeight(3);
  line(0, bottomY, plotWidth, bottomY);
  strokeWeight(1); 

  // 【下半分】スペクトルの描画（黄色いバー）
  strokeWeight(1);
  int maxDisplayBins = min(fft.specSize(), 80); 
  float barWidth = float(plotWidth) / maxDisplayBins;

  fill(255, 200, 0, 200);

  float allowedRegionHeight = areaBottomY - bottomY;
  float absoluteMaxHeight = allowedRegionHeight - 50; 

  float highestAmplitudeInFrame = 0;
  for (int i = 0; i < maxDisplayBins; i++) {
    float amp = fft.getBand(i);
    if (amp > highestAmplitudeInFrame) {
      highestAmplitudeInFrame = amp;
    }
  }

  if (highestAmplitudeInFrame < 10.0) {
    highestAmplitudeInFrame = 40.0; 
  }

  for (int i = 0; i < maxDisplayBins; i++) {
    float amplitude = fft.getBand(i);
    float barHeight = map(amplitude, 0, highestAmplitudeInFrame, 0, absoluteMaxHeight);
    barHeight = constrain(barHeight, 0, absoluteMaxHeight);

    stroke(0, 50); 
    rect(i * barWidth, areaBottomY - barHeight, barWidth, barHeight);
  }
}

void drawInfoPanel() {
  int xInfoStart = width / 2;
  int pnlActualWidth = width - xInfoStart;

  fill(30);
  noStroke();
  rect(xInfoStart, 0, pnlActualWidth, height);

  stroke(100);
  strokeWeight(3);
  line(xInfoStart, 0, xInfoStart, height);
  strokeWeight(1);

  fill(200);
  textAlign(LEFT, CENTER);

  // 1. 現在のBPM
  textSize(24);
  text("現在のBPM", xInfoStart + 40, height * 0.1);
  textSize(50);
  fill(255);
  // ★ currentBPM だった場所を、Arduinoの変数「bpm」に変更
  text(bpm + " BPM", xInfoStart + 40, height * 0.17);

  // 2. 現在の周波数
  fill(200);
  textSize(24);
  text("現在の周波数", xInfoStart + 40, height * 0.33);
  textSize(50);
  fill(255);
  if (isSoundPlaying) {
    text(nf(currentFrequency, 0, 1) + " Hz", xInfoStart + 40, height * 0.4);
  } else {
    text("-", xInfoStart + 40, height * 0.4);
  }

  // 3. 音階 / 種類
  fill(200);
  textSize(24);
  text("音階 / 種類", xInfoStart + 40, height * 0.6);

  // 大きく種類（音階）を表示
  textAlign(CENTER, CENTER);
  textSize(90); 
  fill(255, 200, 0); 
  text(currentPitchText, xInfoStart + pnlActualWidth / 2, height * 0.76);
  
  // 録音中のマークも右上に小さく出るようにします
  if (isRecording) {
    fill(255, 0, 0);
    textSize(24);
    textAlign(LEFT, TOP);
    text("● REC", xInfoStart + 40, 20);
  }
}
