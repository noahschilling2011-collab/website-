/*
 * ============================================================
 *  KONFIGURATION — hier musst DU etwas eintragen!
 * ============================================================
 *  Diese Datei ist die einzige, die du anpassen musst,
 *  damit das Radar bei dir zu Hause / in der Schule läuft.
 */

#pragma once

// ------------------------------------------------------------
// 1) WLAN-Zugangsdaten
//    Achtung: Der ESP32 kann nur 2,4-GHz-WLAN (kein 5 GHz)!
// ------------------------------------------------------------
#define WIFI_SSID     "DEIN_WLAN_NAME"
#define WIFI_PASSWORT "DEIN_WLAN_PASSWORT"

// ------------------------------------------------------------
// 2) Dein Standort = Mittelpunkt des Radars
//    Einfach herausfinden: Google Maps -> Rechtsklick auf
//    deinen Ort -> die beiden Zahlen anklicken (kopiert sie).
//    Erste Zahl = Breitengrad (LAT), zweite = Laengengrad (LON)
// ------------------------------------------------------------
#define HOME_LAT 51.3397   // Beispiel: Leipzig
#define HOME_LON 12.3731

// ------------------------------------------------------------
// 3) Radar-Reichweite in Seemeilen (nautische Meilen, NM)
//    1 NM = 1,852 km  ->  40 NM sind ca. 74 km Umkreis
//    Erlaubt: 1 bis 250
// ------------------------------------------------------------
#define RADAR_RADIUS_NM 40

// ------------------------------------------------------------
// 4) Wie oft neue Flugdaten geholt werden (Millisekunden)
//    15000 = alle 15 Sekunden. Bitte nicht unter 5000 stellen,
//    damit wir den kostenlosen Server nicht ueberlasten.
// ------------------------------------------------------------
#define UPDATE_INTERVALL_MS 15000
