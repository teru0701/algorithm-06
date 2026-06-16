#include <Wire.h>

// ---- このボードのI2Cアドレス（楽器ごとに変更） ----
const uint8_t I2C_ADDRESS = 0x10;  // 楽器2は0x20、楽器3は0x30、楽器4は0x40

// ---- 楽譜「カエルの歌」演奏時間計算用 ----
const float noteDuration[] = {
  1.0,  1.0,  1.0,  1.0,
  1.0,  1.0,  1.0,
  1.0,  1.0,  1.0,  1.0,
  1.0,  1.0,  1.0,
  1.0,  1.0,
  1.0,  1.0,
  0.5,  0.5,  0.5,  0.5,  0.5,  0.5,  0.5,  0.5,
  1.0,  1.0,  1.0
};
const float noteTime[] = {
  0.0,  1.0,  2.0,  3.0,
  4.0,  5.0,  6.0,
  8.0,  9.0, 10.0, 11.0,
 12.0, 13.0, 14.0,
 16.0, 18.0,
 20.0, 22.0,
 24.0, 24.5, 25.0, 25.5, 26.0, 26.5, 27.0, 27.5,
 28.0, 29.0, 30.0
};
const String note[] = {
  "C4", "D4", "E4", "F4",
  "E4", "D4", "C4",
  "E4", "F4", "G4", "A4",
  "G4", "F4", "E4",
  "C4", "C4",
  "C4", "C4",
  "C4", "C4", "D4", "D4", "E4", "E4", "F4", "F4",
  "E4", "D4", "C4"
};

const int NOTE_COUNT = sizeof(noteDuration) / sizeof(noteDuration[0]);
int currentNote = 0;
int allowedBars = 0;

// ---- 演奏状態 ----
bool          isPlaying    = false;
unsigned long startTime    = 0;
unsigned long beat         = 500;
float         BPM          = 120.0;

// ---- I2C受信バッファ ----
volatile uint8_t rxBuf[3]     = {0, 0, 0};
volatile bool    packetReady  = false;
volatile uint8_t finishedFlag = 0;

// ============================================================
// I2C受信コールバック（指揮者→楽器）
// ============================================================
void onReceive(int numBytes) {
  if (numBytes < 3) {
    while (Wire.available()) Wire.read();  // 不完全パケット破棄
    return;
  }
  rxBuf[0] = Wire.read();
  rxBuf[1] = Wire.read();
  rxBuf[2] = Wire.read();
  packetReady = true;
}

// ============================================================
// I2C送信コールバック（楽器→指揮者、終了フラグを返す）
// ============================================================
void onRequest() {
  Wire.write(finishedFlag);
}

// ============================================================
// setup
// ============================================================
void setup() {
  Serial.begin(115200);
  while (!Serial) { ; }

  Wire.begin(I2C_ADDRESS);       // スレーブとして起動
  Wire.onReceive(onReceive);     // 受信コールバック登録
  Wire.onRequest(onRequest);     // 送信コールバック登録

  Serial.print("=== 楽器側 I2C受信待機中 アドレス:0x");
  Serial.print(I2C_ADDRESS, HEX);
  Serial.println(" (UNO R4 WiFi) ===");
}

// ============================================================
// loop
// ============================================================
void loop() {

  // ----------------------------------------------------------
  // パケット検証 → 演奏開始/停止
  // ----------------------------------------------------------
  if (packetReady) {
    uint8_t header   = rxBuf[0];
    uint8_t bpmByte  = rxBuf[1];
    uint8_t checksum = rxBuf[2];

    if ((header ^ bpmByte) == checksum && (header == 0xAA || header == 0x00 || header == 0xBB)) {

      if (header == 0xAA) {
        BPM          = (float)bpmByte;
        beat         = (unsigned long)(60000.0f / BPM);
        startTime    = millis();
        isPlaying    = true;
        finishedFlag = 0;
        currentNote  = 0;
        allowedBars  = 1;

        Serial.print("[");
        Serial.print(startTime);
        Serial.print("ms] BPM受信: ");
        Serial.print(BPM);
        Serial.println(" → 演奏開始");

      } else if (header == 0xBB) {
        if (isPlaying) {
          allowedBars++;
          BPM          = (float)bpmByte;
          beat         = (unsigned long)(60000.0f / BPM);
          
          startTime    = millis() - ((allowedBars - 1) * 4.0f * (float)beat);

          Serial.print("[");
          Serial.print(millis());
          Serial.print("ms] リアルタイムBPM変更: ");
          Serial.println(BPM);
        }
      } else {
        isPlaying = false;
        Serial.print("[");
        Serial.print(millis());
        Serial.println("ms] 停止指示を受信");
      }

    } else {
      Serial.print("[");
      Serial.print(millis());
      Serial.print("ms] チェックサムエラー：");
      Serial.print(header, HEX);
      Serial.print(" ");
      Serial.print(bpmByte, HEX);
      Serial.print(" ");
      Serial.println(checksum, HEX);
    }

    packetReady = false;
  }

  // ----------------------------------------------------------
  // 演奏タイマー監視 ＆ Processingへのデータ送信
  // ----------------------------------------------------------
  if (isPlaying) {
    unsigned long elapsed = millis() - startTime;
    float currentPositionInBars = (float)elapsed / (4.0f * (float)beat);

    if (currentPositionInBars >= (float)allowedBars) {
      return;
    }

    if (currentNote < NOTE_COUNT) {
      if (elapsed >= (unsigned long)(noteTime[currentNote] * (float)beat)) {
        Serial.print(BPM);
        Serial.print(",");
        Serial.print(note[currentNote]);
        Serial.print(",");
        Serial.println(noteDuration[currentNote]);
        currentNote++;
      }
    }

    unsigned long endTime =
      (unsigned long)((noteTime[NOTE_COUNT - 1] + noteDuration[NOTE_COUNT - 1]) * (float)beat);

    if (elapsed >= endTime) {
      isPlaying    = false;
      finishedFlag = 1;
      currentNote  = 0;
      allowedBars  = 0;

      Serial.print("["); Serial.print(millis());
      Serial.println("ms] 演奏終了 → finishedFlag=1 を指揮者に返す");
    }
  }
}
