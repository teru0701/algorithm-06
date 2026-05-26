/*
バイオリンの波形を生成します
倍音構成,ビブラート,デチューン3波形の合成,ノイズ,モーグフィルタ,ADSRエンベロープ,ディレイを行います
rキーで録音が可能です
シリアル通信でArduinoから送られた瞬間その音がなります
*/

import ddf.minim.*; 
import ddf.minim.ugens.*;
import processing.serial.*;

Minim minim;
AudioOutput out;
Waveform currentWaveform; // 音色格納用変数
String frequency; // 周波数格納変数
Serial myPort;  // シリアル通信

// Arduinoから送られた値を格納する変数
float bpm = 0.0f;  // BPM
String note = "";  // 音階
float noteLength = 0.0f; // 長さ

// 録音用
AudioRecorder recorder;
boolean isRecording = false;

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
      lfoVibrato[i] = new Oscil(5.8f + 0.15f*i, 2.0f, Waves.SINE);
      // LFO(ビブラート用)のエンベロープの設定 (最大振幅, A, D, S, R)
      vibratoAdsr[i] = new ADSR(1.0, 0.5, 0.0, 1.0, 0.2);
      lfoVibrato[i].patch( vibratoAdsr[i] );
      // 基本の周波数を設定
      baseFreq[i] = new Constant(frequency + detune[i]);
      // 基本の周波数を追加
      baseFreq[i].patch( freqSummer[i] );
      // ±2Hzの揺れを追加
      vibratoAdsr[i].patch( freqSummer[i] );
      
      if(i==1){
      // 音信号を作成(周波数, 振幅0~1, 音色)
      wave[i] = new Oscil(frequency, 0.4f, wf);
      }else{
      wave[i] = new Oscil(frequency, 0.25f, wf);
      }
      // 波形の開始地点をランダムに設定
      wave[i].setPhase( random(0, 1) );
      // LFO(ビブラート用)を各音信号の周波数に代入
      freqSummer[i].patch( wave[i].frequency ); 
      // 各音信号をSummerへ合成
      wave[i].patch( waveSummer );
    }
    
    // 2.ノイズを追加
    
    // ピンクノイズを作成(振幅0~1, ノイズの種類)
    pinkNoise = new Noise(0.01, Noise.Tint.PINK);
    pinkNoise.patch( waveSummer );
    
    // 3.モーグフィルタ(ローパスフィルタ)の追加
    
    // フィルタを作成(カットオフ周波数, レゾナンス0~1, フィルタの種類)
    moogFilter = new MoogFilter(3000.0f, 0.0f, MoogFilter.Type.LP);
    waveSummer.patch( moogFilter );
        
    // 4.ディレイの追加
    
    // ディレイの作成(遅れる時間, 音の大きさ0~1, 繰り返すか, 元の音を出力に混ぜるか)
    delay = new Delay( 0.4f, 0.05f, true, true );
    moogFilter.patch( delay );
    
    // 5.エンベロープの制御
    
    // エンベロープの設定(最大振幅, A, D, S, R)
    adsr = new ADSR(maxAmp, 0.5, 0.0, 1.0, 0.2);
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
  size(512, 200);
  printArray(Serial.list());  // シリアルポートのリストを表示
  myPort = new Serial(this, Serial.list()[1], 115200);  // シリアルポートと通信速度を指定
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
      new float[] { 1.000f, 0.355f, 0.251f, 0.158f, 0.355f, 
                    0.141f, 0.063f, 0.126f, 0.141f, 0.016f,
                    0.018f, 0.022f, 0.007f, 0.014f, 0.009f,
                    0.014f, 0.009f, 0.007f, 0.004f, 0.005f }  //バイオリン
      );
      
  recorder = minim.createRecorder(out, "my_violin.wav"); // 録音用
}

void playSong() {
  // 再生を停止
  out.pauseNotes();
   // 音を追加(開始時刻，音の長さ，Instrumentのインスタンス)
   out.playNote(0.0f, noteLength,
     new HackInstrument(Frequency.ofPitch( note ).asHz(),
       0.5f, currentWaveform));
   out.playNote(8.0f, noteLength,
     new HackInstrument(Frequency.ofPitch( note ).asHz(),
       0.5f, currentWaveform));
   /*out.playNote(16.0f, noteLength,
     new HackInstrument(Frequency.ofPitch( note ).asHz(),
       0.5f, currentWaveform));*/
  // 再生
  out.resumeNotes(); 
}

void draw() 
{
  background (0); 
  stroke (255);

  // 左チャンネルと右チャンネルに入っている波形を描画 
  for (int i = 0; i < out.bufferSize() - 1; i++)
  {
    line( i, 50 + out.left.get(i)*50, i+1, 50 + out.left.get(i+1)*50 );
    line( i, 150 + out.right.get(i)*50, i+1, 150 + out.right.get(i+1)*50 ); 
  }
  if (isRecording) {
    fill(255, 0, 0);
    text("REC", 10, 20);
  }
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
