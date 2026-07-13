//  ============================================================
//  TFT_eSPI-Konfiguration fuer das "Cheap Yellow Display" (CYD)
//  Board-Bezeichnung: ESP32-2432S028R
//  (ESP32 + 2,8"-Touch-Display auf einer Platine, ca. 12-15 Euro)
//  ============================================================
//
//  ANLEITUNG:
//  1. Finde den Ordner der TFT_eSPI-Bibliothek:
//     Windows:  Dokumente\Arduino\libraries\TFT_eSPI
//     macOS:    ~/Documents/Arduino/libraries/TFT_eSPI
//  2. Benenne dort die Datei "User_Setup.h" um in "User_Setup_ALT.h"
//     (als Sicherung).
//  3. Kopiere DIESE Datei dorthin und benenne sie um in "User_Setup.h".
//  4. Arduino IDE neu starten - fertig!
//
//  Hinweis: Falls die Farben falsch aussehen (blau statt orange),
//  aendere unten TFT_BGR in TFT_RGB (oder umgekehrt) - es gibt
//  zwei CYD-Varianten mit unterschiedlichen Displays.
//  ============================================================

#define USER_SETUP_INFO "CYD ESP32-2432S028R Flugzeugradar"

// Display-Treiber-Chip
#define ILI9341_2_DRIVER

// Groesse des Displays
#define TFT_WIDTH  240
#define TFT_HEIGHT 320

// So ist das Display auf der CYD-Platine verdrahtet (nicht aendern!)
#define TFT_MISO 12
#define TFT_MOSI 13
#define TFT_SCLK 14
#define TFT_CS   15
#define TFT_DC    2
#define TFT_RST  -1
#define TFT_BL   21              // Hintergrundbeleuchtung
#define TFT_BACKLIGHT_ON HIGH

// Farbreihenfolge (bei falschen Farben: TFT_RGB probieren)
#define TFT_RGB_ORDER TFT_BGR

// Schriftarten laden
#define LOAD_GLCD
#define LOAD_FONT2
#define LOAD_FONT4
#define LOAD_FONT6
#define LOAD_FONT7
#define LOAD_FONT8
#define LOAD_GFXFF
#define SMOOTH_FONT

// Geschwindigkeit der Datenuebertragung zum Display
#define SPI_FREQUENCY       55000000
#define SPI_READ_FREQUENCY  20000000
#define SPI_TOUCH_FREQUENCY  2500000
