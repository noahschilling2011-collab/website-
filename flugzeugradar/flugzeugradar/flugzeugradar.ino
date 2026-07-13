/*
 * ============================================================
 *  IT.3-M.26/1 — "Geheimagent, oder was?"
 *  FLUGZEUGRADAR mit ESP32 und Display
 * ============================================================
 *
 *  So funktioniert es:
 *   1. Der ESP32 verbindet sich mit deinem WLAN.
 *   2. Alle 15 Sekunden fragt er einen kostenlosen Server
 *      (api.adsb.lol) nach allen Flugzeugen in deiner Naehe.
 *      Die Daten stammen aus ADS-B-Signalen, die jedes
 *      Flugzeug staendig aussendet (Position, Hoehe, ...).
 *   3. Das Display zeigt die Flugzeuge wie auf einem echten
 *      Radar: gruener Suchstrahl, Entfernungsringe und kleine
 *      Dreiecke, die in Flugrichtung zeigen.
 *
 *  Benoetigte Bibliotheken (Arduino IDE -> Bibliotheksverwalter):
 *   - TFT_eSPI     (von Bodmer)          -> Display ansteuern
 *   - ArduinoJson  (von Benoit Blanchon) -> Antwort des Servers lesen
 *
 *  WLAN-Name, Passwort und Standort traegst du in config.h ein!
 *  Die Anleitung zum Display-Setup steht in der README.md.
 * ============================================================
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <TFT_eSPI.h>
#include "config.h"

// ------------------------------------------------------------
// Display: 320 x 240 Pixel im Querformat.
// Links das runde Radar (240 x 240), rechts die Info-Leiste.
// ------------------------------------------------------------
TFT_eSPI tft = TFT_eSPI();
TFT_eSprite radar = TFT_eSprite(&tft);  // Zwischenspeicher gegen Flackern

const int RADAR_GROESSE = 240;               // Breite/Hoehe des Radarfelds
const int CX = RADAR_GROESSE / 2;            // Mittelpunkt X
const int CY = RADAR_GROESSE / 2;            // Mittelpunkt Y
const int R  = RADAR_GROESSE / 2 - 4;        // Radius des aeussersten Rings
const int PANEL_X = RADAR_GROESSE;           // linke Kante der Info-Leiste

// ------------------------------------------------------------
// Datenstruktur: alles, was wir uns pro Flugzeug merken
// ------------------------------------------------------------
struct Flugzeug {
  char  rufzeichen[10];  // z.B. "DLH4KA" (Lufthansa-Flug)
  float lat, lon;        // Position (Breiten-/Laengengrad)
  int   hoeheFuss;       // Flughoehe in Fuss, -1 = am Boden
  int   knoten;          // Geschwindigkeit in Knoten
  int   kurs;            // Flugrichtung in Grad (0 = Norden)
  float distanzKm;       // Entfernung zu uns in km
};

const int MAX_FLUGZEUGE = 30;
Flugzeug flugzeuge[MAX_FLUGZEUGE];
int anzahlFlugzeuge = 0;

unsigned long letzteAbfrage = 0;   // wann kamen zuletzt Daten?
bool  datenOk     = false;         // war die letzte Abfrage erfolgreich?
float sweepWinkel = 0;             // aktueller Winkel des Suchstrahls

// ============================================================
// SETUP — laeuft einmal beim Einschalten
// ============================================================
void setup() {
  Serial.begin(115200);
  Serial.println("\n=== GEHEIMAGENT-FLUGZEUGRADAR ===");

  tft.init();
  tft.setRotation(1);          // Querformat (320 breit, 240 hoch)
  tft.fillScreen(TFT_BLACK);

  // --- Startbildschirm im Agenten-Stil ---
  tft.setTextDatum(MC_DATUM);  // Text an der Mitte ausrichten
  tft.setTextColor(TFT_RED, TFT_BLACK);
  tft.drawString("* TOP SECRET *", 160, 60, 4);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.drawString("FLUGZEUGRADAR", 160, 100, 4);
  tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
  tft.drawString("IT.3 - Geheimagent, oder was?", 160, 130, 2);

  // --- WLAN verbinden ---
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.drawString("Verbinde mit WLAN ...", 160, 170, 2);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORT);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(250);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWLAN verbunden! IP: " + WiFi.localIP().toString());
    tft.drawString("WLAN verbunden!      ", 160, 170, 2);
  } else {
    Serial.println("\nFEHLER: Kein WLAN! Pruefe config.h");
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.drawString("KEIN WLAN - config.h pruefen!", 160, 170, 2);
  }
  delay(1200);

  // --- Zwischenspeicher fuer das Radar anlegen ---
  // 8-Bit-Farben sparen Speicher (240x240 Pixel = ca. 58 KB RAM)
  radar.setColorDepth(8);
  if (radar.createSprite(RADAR_GROESSE, RADAR_GROESSE) == nullptr) {
    Serial.println("FEHLER: Zu wenig RAM fuer das Radarbild!");
  }

  tft.fillScreen(TFT_BLACK);
  zeichnePanel();
}

// ============================================================
// LOOP — laeuft immer wieder
// ============================================================
void loop() {
  // 1) WLAN weg? -> neu verbinden
  if (WiFi.status() != WL_CONNECTED) {
    WiFi.reconnect();
  }

  // 2) Ist es Zeit fuer neue Flugdaten?
  if (letzteAbfrage == 0 || millis() - letzteAbfrage >= UPDATE_INTERVALL_MS) {
    datenOk = holeFlugdaten();
    letzteAbfrage = millis();
    zeichnePanel();
  }

  // 3) Info-Leiste jede Sekunde auffrischen (Sekundenzaehler)
  static unsigned long letztesPanel = 0;
  if (millis() - letztesPanel >= 1000) {
    letztesPanel = millis();
    zeichnePanel();
  }

  // 4) Suchstrahl weiterdrehen und Radar neu zeichnen
  sweepWinkel += 2.5;
  if (sweepWinkel >= 360) sweepWinkel -= 360;
  zeichneRadar();

  delay(25);  // ca. 30 Bilder pro Sekunde
}

// ============================================================
// FLUGDATEN HOLEN — fragt den ADS-B-Server ab
// ============================================================
bool holeFlugdaten() {
  if (WiFi.status() != WL_CONNECTED) return false;

  // Web-Adresse zusammenbauen: Position + Radius
  char url[128];
  snprintf(url, sizeof(url), "https://api.adsb.lol/v2/point/%.4f/%.4f/%d",
           (double)HOME_LAT, (double)HOME_LON, (int)RADAR_RADIUS_NM);
  Serial.println(String("Frage ab: ") + url);

  WiFiClientSecure client;
  client.setInsecure();   // Zertifikat nicht pruefen (reicht fuer unser Projekt)

  HTTPClient http;
  http.useHTTP10(true);   // wichtig, damit wir die Antwort als Strom lesen koennen
  http.setTimeout(10000);
  if (!http.begin(client, url)) return false;

  int code = http.GET();
  if (code != 200) {
    Serial.println("Server-Fehler, Code: " + String(code));
    http.end();
    return false;
  }

  // Filter: Aus der grossen Antwort brauchen wir nur wenige Felder.
  // Das spart jede Menge Arbeitsspeicher!
  JsonDocument filter;
  filter["ac"][0]["hex"]      = true;  // eindeutige Kennung
  filter["ac"][0]["flight"]   = true;  // Rufzeichen, z.B. "DLH4KA"
  filter["ac"][0]["lat"]      = true;  // Breitengrad
  filter["ac"][0]["lon"]      = true;  // Laengengrad
  filter["ac"][0]["alt_baro"] = true;  // Hoehe in Fuss (oder "ground")
  filter["ac"][0]["gs"]       = true;  // Geschwindigkeit in Knoten
  filter["ac"][0]["track"]    = true;  // Flugrichtung in Grad

  JsonDocument doc;
  DeserializationError fehler =
      deserializeJson(doc, http.getStream(), DeserializationOption::Filter(filter));
  http.end();

  if (fehler) {
    Serial.println(String("JSON-Fehler: ") + fehler.c_str());
    return false;
  }

  // Antwort durchgehen und die naechsten Flugzeuge einsammeln
  anzahlFlugzeuge = 0;
  for (JsonObject ac : doc["ac"].as<JsonArray>()) {
    if (!ac["lat"].is<float>() || !ac["lon"].is<float>()) continue;

    Flugzeug f;
    f.lat = ac["lat"].as<float>();
    f.lon = ac["lon"].as<float>();
    f.distanzKm = entfernungKm(f.lat, f.lon);

    // Rufzeichen (falls keins gesendet wird: die Hex-Kennung nehmen)
    const char* name = ac["flight"] | ac["hex"] | "???";
    strncpy(f.rufzeichen, name, sizeof(f.rufzeichen) - 1);
    f.rufzeichen[sizeof(f.rufzeichen) - 1] = '\0';
    // Leerzeichen am Ende abschneiden ("DLH4KA  " -> "DLH4KA")
    for (int i = strlen(f.rufzeichen) - 1; i >= 0 && f.rufzeichen[i] == ' '; i--)
      f.rufzeichen[i] = '\0';

    // Hoehe: Zahl in Fuss ODER das Wort "ground" (= steht am Boden)
    f.hoeheFuss = ac["alt_baro"].is<float>() ? (int)ac["alt_baro"].as<float>() : -1;
    // Achtung: gs/track kommen als Kommazahl -> erst als float lesen!
    f.knoten    = (int)(ac["gs"]    | 0.0f);
    f.kurs      = (int)(ac["track"] | 0.0f);

    // Einsortieren: die Liste bleibt nach Entfernung sortiert,
    // und wenn sie voll ist, fliegt das am weitesten entfernte raus.
    int pos = anzahlFlugzeuge;
    if (pos >= MAX_FLUGZEUGE) pos = MAX_FLUGZEUGE - 1;         // letzter Platz
    if (pos < anzahlFlugzeuge && f.distanzKm >= flugzeuge[pos].distanzKm)
      continue;                                                 // weiter weg als alle
    while (pos > 0 && flugzeuge[pos - 1].distanzKm > f.distanzKm) {
      flugzeuge[pos] = flugzeuge[pos - 1];                      // Platz machen
      pos--;
    }
    flugzeuge[pos] = f;
    if (anzahlFlugzeuge < MAX_FLUGZEUGE) anzahlFlugzeuge++;
  }

  Serial.println(String("Gefunden: ") + anzahlFlugzeuge + " Flugzeuge");
  return true;
}

// ============================================================
// MATHE-HELFER
// ============================================================

// Entfernung von uns zum Flugzeug in km (fuer kurze Strecken genau genug)
float entfernungKm(float lat, float lon) {
  float dxOst  = (lon - HOME_LON) * 111.32f * cosf(HOME_LAT * DEG_TO_RAD);
  float dyNord = (lat - HOME_LAT) * 110.574f;
  return sqrtf(dxOst * dxOst + dyNord * dyNord);
}

// Rechnet Breiten-/Laengengrad in eine Pixel-Position auf dem Radar um.
// Gibt false zurueck, wenn das Flugzeug ausserhalb des Radars liegt.
bool positionAufRadar(float lat, float lon, int* x, int* y) {
  float reichweiteKm = RADAR_RADIUS_NM * 1.852f;
  float dxOst  = (lon - HOME_LON) * 111.32f * cosf(HOME_LAT * DEG_TO_RAD);
  float dyNord = (lat - HOME_LAT) * 110.574f;
  if (sqrtf(dxOst * dxOst + dyNord * dyNord) > reichweiteKm) return false;
  *x = CX + (int)(dxOst  / reichweiteKm * R);
  *y = CY - (int)(dyNord / reichweiteKm * R);   // Bildschirm-Y zeigt nach unten!
  return true;
}

// ============================================================
// RADAR ZEICHNEN — das Herzstueck
// ============================================================
void zeichneRadar() {
  radar.fillSprite(TFT_BLACK);

  // --- 1) Nachleuchten des Suchstrahls (wird nach hinten dunkler) ---
  for (int i = 45; i >= 0; i--) {
    float winkel = sweepWinkel - i * 1.6f;
    float rad = (winkel - 90) * DEG_TO_RAD;     // 0 Grad = Norden = oben
    uint16_t farbe = radar.color565(0, 200 - i * 4, 0);
    radar.drawLine(CX, CY, CX + cosf(rad) * R, CY + sinf(rad) * R, farbe);
  }

  // --- 2) Entfernungsringe und Fadenkreuz ---
  uint16_t ringFarbe = radar.color565(0, 110, 0);
  for (int i = 1; i <= 4; i++)
    radar.drawCircle(CX, CY, R * i / 4, ringFarbe);
  radar.drawLine(CX - R, CY, CX + R, CY, ringFarbe);
  radar.drawLine(CX, CY - R, CX, CY + R, ringFarbe);

  // Himmelsrichtungen
  radar.setTextColor(radar.color565(0, 160, 0));
  radar.setTextDatum(MC_DATUM);
  radar.drawString("N", CX, 8, 1);
  radar.drawString("S", CX, RADAR_GROESSE - 8, 1);
  radar.drawString("W", 8, CY, 1);
  radar.drawString("O", RADAR_GROESSE - 8, CY, 1);

  // --- 3) Flugzeuge einzeichnen ---
  for (int i = 0; i < anzahlFlugzeuge; i++) {
    int x, y;
    if (!positionAufRadar(flugzeuge[i].lat, flugzeuge[i].lon, &x, &y)) continue;

    // Farbe je nach Flughoehe (siehe Legende in der README):
    uint16_t farbe;
    if      (flugzeuge[i].hoeheFuss < 0)      farbe = TFT_DARKGREY; // am Boden
    else if (flugzeuge[i].hoeheFuss < 10000)  farbe = TFT_ORANGE;   // niedrig
    else if (flugzeuge[i].hoeheFuss < 25000)  farbe = TFT_YELLOW;   // mittel
    else                                      farbe = TFT_GREEN;    // Reiseflug

    zeichneFlugzeugSymbol(x, y, flugzeuge[i].kurs, farbe);

    // Rufzeichen daneben schreiben
    radar.setTextColor(TFT_WHITE);
    radar.setTextDatum(ML_DATUM);
    radar.drawString(flugzeuge[i].rufzeichen, x + 8, y, 1);
  }

  // --- 4) Heller Suchstrahl ganz oben drueber ---
  float rad = (sweepWinkel - 90) * DEG_TO_RAD;
  radar.drawLine(CX, CY, CX + cosf(rad) * R, CY + sinf(rad) * R, TFT_GREEN);
  radar.fillCircle(CX, CY, 3, TFT_GREEN);   // wir in der Mitte

  // Fertiges Bild in einem Rutsch aufs Display schieben (kein Flackern)
  radar.pushSprite(0, 0);
}

// Kleines Dreieck, dessen Spitze in Flugrichtung zeigt
void zeichneFlugzeugSymbol(int x, int y, int kurs, uint16_t farbe) {
  float rad = (kurs - 90) * DEG_TO_RAD;
  int sx = x + cosf(rad) * 6, sy = y + sinf(rad) * 6;                   // Spitze
  int lx = x + cosf(rad + 2.5f) * 5, ly = y + sinf(rad + 2.5f) * 5;     // hinten links
  int rx = x + cosf(rad - 2.5f) * 5, ry = y + sinf(rad - 2.5f) * 5;     // hinten rechts
  radar.fillTriangle(sx, sy, lx, ly, rx, ry, farbe);
}

// ============================================================
// INFO-LEISTE rechts neben dem Radar
// ============================================================
void zeichnePanel() {
  tft.fillRect(PANEL_X, 0, 320 - PANEL_X, 240, TFT_BLACK);
  tft.drawFastVLine(PANEL_X, 0, 240, TFT_DARKGREY);

  int x = PANEL_X + 6;
  tft.setTextDatum(TL_DATUM);

  tft.setTextColor(TFT_RED, TFT_BLACK);
  tft.drawString("GEHEIM", x, 6, 2);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.drawString("RADAR", x, 24, 2);
  tft.drawFastHLine(PANEL_X, 46, 80, TFT_DARKGREY);

  // Anzahl der erfassten Flugzeuge
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.drawString("ZIELE:", x, 54, 1);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.drawString(String(anzahlFlugzeuge), x + 42, 54, 1);

  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.drawString("RADIUS:", x, 68, 1);
  tft.setTextColor(TFT_GREEN, TFT_BLACK);
  tft.drawString(String((int)RADAR_RADIUS_NM) + " NM", x + 46, 68, 1);
  tft.drawFastHLine(PANEL_X, 82, 80, TFT_DARKGREY);

  // Das naechste (dichteste) Flugzeug im Detail
  tft.setTextColor(TFT_YELLOW, TFT_BLACK);
  tft.drawString("KONTAKT:", x, 90, 1);
  if (anzahlFlugzeuge > 0) {
    Flugzeug& f = flugzeuge[0];   // Liste ist nach Entfernung sortiert
    tft.setTextColor(TFT_WHITE, TFT_BLACK);
    tft.drawString(f.rufzeichen, x, 104, 2);
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
    tft.drawString(String(f.distanzKm, 1) + " km", x, 124, 1);
    if (f.hoeheFuss >= 0)
      tft.drawString(String(f.hoeheFuss) + " ft", x, 138, 1);
    else
      tft.drawString("am Boden", x, 138, 1);
    tft.drawString(String(f.knoten) + " kt", x, 152, 1);
  } else {
    tft.setTextColor(TFT_DARKGREY, TFT_BLACK);
    tft.drawString("---", x, 104, 2);
  }
  tft.drawFastHLine(PANEL_X, 170, 80, TFT_DARKGREY);

  // Farb-Legende (Flughoehe)
  tft.fillCircle(x + 3, 181, 3, TFT_ORANGE);
  tft.setTextColor(TFT_WHITE, TFT_BLACK);
  tft.drawString("niedrig", x + 12, 177, 1);
  tft.fillCircle(x + 3, 195, 3, TFT_YELLOW);
  tft.drawString("mittel", x + 12, 191, 1);
  tft.fillCircle(x + 3, 209, 3, TFT_GREEN);
  tft.drawString("hoch", x + 12, 205, 1);

  // Statuszeile: WLAN + Alter der Daten
  if (WiFi.status() == WL_CONNECTED && datenOk) {
    tft.setTextColor(TFT_GREEN, TFT_BLACK);
    int sek = (millis() - letzteAbfrage) / 1000;
    tft.drawString("OK  " + String(sek) + "s", x, 226, 1);
  } else {
    tft.setTextColor(TFT_RED, TFT_BLACK);
    tft.drawString(WiFi.status() == WL_CONNECTED ? "SERVER?" : "KEIN WLAN", x, 226, 1);
  }
}
