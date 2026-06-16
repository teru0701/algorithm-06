import ddf.minim.*; 
import ddf.minim.analysis.*;
import ddf.minim.ugens.*;
import processing.serial.*;

Minim minim;
AudioOutput out;
Waveform currentWaveform; // 音色格納用変数
Serial myPort;  // シリアル通信

FFT fft;
PFont jpFont;                        // 日本語を出すためのフォント
float topMargin = 50;

// Arduinoから送られた値を格納する変数
float bpm = 0.0f;  // BPM初期値
String drumType = "-";  // 楽器の種類（Kick, Snare, Hatなど）

// 録音用
AudioRecorder recorder;
boolean isRecording = false;

// ドラムの音色を変更するためにInstrument インタフェースを実装 
class HackInstrument implements Instrument {
  
  Oscil[] wave = new Oscil[3]; // 3つの音信号の波形
  float[] detune = {-0.25f, 0.0f, 0.25f}; // デチューンのそれぞれのズレ
  Summer[] freqSummer = new Summer[3]; // 周波数を合成する変数
  Constant[] baseFreq = new Constant[3]; // 基本となる周波数
  Summer waveSummer; // 3つの波形を合成する変数
  
  Noise pinkNoise; // ノイズ変数
  MoogFilter moogFilter; // モーグフィルタ変数
  ADSR adsr; // エンベロープ変数
  Delay delay; // ディレイ変数
  
  HackInstrument( float frequency, float maxAmp, Waveform wf, String types ) { 
    
    waveSummer = new Summer();
   
    for (int i = 0; i < 3; i++) {
      freqSummer[i] = new Summer();
      
      //キック周波数の設定
      if(types.equals("Kick")){
        baseFreq[i] = new Constant(55 + detune[i]);
      }else{
        baseFreq[i] = new Constant(frequency + detune[i]);
      }
      baseFreq[i].patch( freqSummer[i] );
      
      //ドラムの音信号を作成
      if(types.equals("Kick")){
        wave[i] = new Oscil(45, 1.0f, wf);
      }else if(types.equals("Hat")){
        wave[i] = new Oscil(8000, 0.08f, wf);
      }else if(types.equals("Snare")){
        wave[i] = new Oscil(250, 0.4f, wf);
      }else if(i==1){
        wave[i] = new Oscil(frequency, 0.5f, wf);
      }else{
        wave[i] = new Oscil(frequency, 0.05f, wf);
      }
      
      // 波形の開始地点をランダムに設定
      wave[i].setPhase( random(0, 1.0) );
      // 周波数合成器をパッチ
      freqSummer[i].patch( wave[i].frequency ); 
      // 各音信号をSummerへ合成
      wave[i].patch( waveSummer );
    }
    
    //ドラムの各種設定
    if(types.equals("Snare")){
      pinkNoise = new Noise(0.22, Noise.Tint.WHITE);
      moogFilter = new MoogFilter(5500.0f, 0.35f, MoogFilter.Type.LP);
      adsr = new ADSR(maxAmp, 0.001, 0.15, 0.001, 0.04);
    }else if(types.equals("Kick")){
      pinkNoise = new Noise(0.05, Noise.Tint.PINK);
      moogFilter = new MoogFilter(2200.0f, 0.75f, MoogFilter.Type.LP);
      adsr = new ADSR(maxAmp, 0.001, 0.30, 0.001, 0.03);
    }else if(types.equals("Hat")){
      pinkNoise = new Noise(0.45, Noise.Tint.WHITE);
      moogFilter = new MoogFilter(12500.0f, 0.08f, MoogFilter.Type.LP);
      adsr = new ADSR(maxAmp, 0.001, 0.01, 0.001, 0.005);
    }else{
      pinkNoise = new Noise(0.025, Noise.Tint.PINK);
      moogFilter = new MoogFilter(2600.0f, 0.18f, MoogFilter.Type.LP);
      adsr = new ADSR(maxAmp, 0.18, 0.10, 0.75, 0.45);
    }

    pinkNoise.patch( waveSummer );
    waveSummer.patch( moogFilter );        
    
    // ディレイの作成
    delay = new Delay( 0.01f, 0.001f, false, true );
    moogFilter.patch( delay );

    delay.patch( adsr );
  }
  
  // コールバック関数:再生開始
  void noteOn(float duration) { 
    adsr.noteOn(); 
    adsr.patch( out );
  }
   
  // コールバック関数:再生停止 
  void noteOff() {  
    adsr.noteOff();
    adsr.unpatchAfterRelease( out );
  }
}
  
void setup() 
{
  fullScreen(); // 全画面表示
  
  printArray(Serial.list());  // シリアルポートのリストを表示
  // 使うポートの番号に合わせて [1] の数字を変更してください
  myPort = new Serial(this, Serial.list()[2], 115200);  
  myPort.bufferUntil('\n');  // 改行されたらシリアルイベントを実行
  
  minim = new Minim(this);
  out = minim.getLineOut();
  out.setTempo( bpm );
  
  // 音色の初期値（ドラム用倍音）
  currentWaveform = WavetableGenerator.gen10(
      4096, 
      new float[] { 1.000f, 0.429f, 0.283f, 0.214f, 0.188f }
      );
      
  recorder = minim.createRecorder(out, "my_drum.wav"); // 録音用
  fft = new FFT(out.bufferSize(), out.sampleRate()); // FFT装置

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
  out.pauseNotes();
  // 長さは送られないため、1拍分（1.0f）の長さで音符を生成します
  out.playNote(0.0f, 1.0f, new HackInstrument(60, 0.8f, currentWaveform, drumType));
  out.resumeNotes(); 
}

void draw() {
  background(30);

  // 音の解析（波形描画用）
  fft.forward(out.mix);

  // 1. 左半分に波形とスペクトルを描く
  drawDrumPlots();       
  // 2. 右半分にBPMや楽器の種類を描く
  drawInfoPanel(); 
}

void serialEvent(Serial p) {
  String inString = p.readStringUntil('\n');
  
  if (inString != null) {
    inString = trim(inString);
    String[] list = split(inString, ',');
    
    // 送られてくるデータが「BPM, 種類」の場合を想定
    if (list.length == 2) {
      bpm = float(list[0]);       // 1つ目: BPM
      drumType = list[1];         // 2つ目: 楽器の種類 (Kick, Snare, Hat)
      
      out.setTempo( bpm );        // BPMの更新
      playSong();                 // ドラム音の再生
      println("受信 -> BPM:" + bpm + " 種類:" + drumType);
    }
  }
}

void keyPressed() { 
  switch (key)
  {
  case 'r': // 'r'キーで録音開始/停止
      if (recorder.isRecording()) {
        recorder.endRecord();
        recorder.save(); 
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

void drawDrumPlots() {
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
    int idx = int(map(i, 0, plotWidth, 0, out.bufferSize()));
    float sample = out.mix.get(idx);

    float x = i;
    float y = (topY + halfHeight / 2) + sample * (halfHeight / 2) * 0.9;
    vertex(x, y);
  }
  endShape();

  // 【区切り線】
  stroke(100);
  strokeWeight(3);
  line(0, bottomY, plotWidth, bottomY);
  strokeWeight(1); 

  // 【下半分】スペクトルの描画（黄色いバー）
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
  text(bpm + " BPM", xInfoStart + 40, height * 0.17);

  // 2. 現在の周波数（※ご要望に基づき「-」固定にしています）
  fill(200);
  textSize(24);
  text("現在の周波数", xInfoStart + 40, height * 0.33);
  textSize(50);
  fill(255);
  text("-", xInfoStart + 40, height * 0.4);

  // 3. 音階 / 種類
  fill(200);
  textSize(24);
  text("音階 / 種類", xInfoStart + 40, height * 0.6);

  // 大きくドラムの種類（Kick, Snare, Hatなど）を表示
  textAlign(CENTER, CENTER);
  textSize(90); 
  fill(255, 200, 0); 
  text(drumType, xInfoStart + pnlActualWidth / 2, height * 0.76);
  
  // 録音中のマーク
  if (isRecording) {
    fill(255, 0, 0);
    textSize(24);
    textAlign(LEFT, TOP);
    text("● REC", xInfoStart + 40, 20);
  }
}
