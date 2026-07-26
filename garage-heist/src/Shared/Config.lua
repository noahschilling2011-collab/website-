--[[
	Config
	Jede Zahl, an der man drehen kann, steht hier. Sonst nirgends.
]]

local Config = {}

-- Wirtschaft ---------------------------------------------------------------
Config.START_CASH = 250 -- reicht fuer das billigste Teil (Reifen T1 = 100) plus Puffer
Config.OFFLINE_CAP_SECONDS = 8 * 60 * 60 -- Deckel fuer Offline-Einnahmen
-- Offline zaehlt nur anteilig: 8h weg gegen 4h Kassendeckel waeren sonst ein
-- Anreiz, das Spiel zu schliessen.
Config.OFFLINE_RATE = 0.6
Config.PILE_CAP_SECONDS = 4 * 60 * 60 -- so lange laeuft der Kassen-Stapel online voll, dann stoppt er
Config.ACCRUAL_TICK = 1 -- Sekunden zwischen Einkommens-Ticks
Config.CASH_PUSH_INTERVAL = 1 -- Sekunden zwischen Cash-Updates an den Client

-- Drosselung der Client-Anfragen (Sekunden). Gilt fuer jedes Remote.
Config.COLLECT_COOLDOWN = 0.3
Config.CLAIM_COOLDOWN = 1
Config.DROP_COOLDOWN = 0.5
Config.PROMPT_COOLDOWN = 1.5
Config.ADMIN_COMMAND_COOLDOWN = 0.3
Config.SELL_REFUND = 0.5 -- Anteil des Teilewerts beim Verkauf loser Teile
-- Beklautwerden soll wehtun, aber nicht bestrafen: das Opfer bekommt einen
-- Teil des Werts sofort als Cash - erst wenn das Teil wirklich abgeliefert ist.
Config.INSURANCE_RATE = 0.25
-- Ein Prototyp laesst sich nicht nachkaufen, nur zurueckholen. Sein Verlust ist
-- damit echter Fortschrittsverlust und nicht bloss ein Rueckschritt in der
-- Kasse - deshalb der deutlich hoehere Satz.
Config.INSURANCE_RATE_T4 = 0.6

-- Hoechste Stufe, die im Werkstatt-Menue kaufbar ist. Alles darueber gibt es
-- ausschliesslich aus fremden oder verlassenen Garagen. Das ist der Kern von
-- v8: vorher war der Heist optional, weil Cash von selbst tickt und bis T4
-- alles bezahlbar war. Jetzt fuehrt der einzige Weg ins Endgame durch das
-- Klau-Fenster.
Config.MAX_PURCHASABLE_TIER = 3

-- Zwischenstufen ("Feinabstimmung") ---------------------------------------
-- Zwischen zwei Tiers liegen zwei kleine Kaeufe. Sie sind KEIN Extra, sondern
-- eine Ratenzahlung: der anschliessende Tier-Sprung wird um das bereits
-- gezahlte guenstiger. Damit wird der Kauftakt dichter, ohne dass die Kurve
-- laenger wird.
Config.SUBTIER_COUNT = 2
Config.SUBTIER_RATE_BONUS = 0.12 -- +12 % Rate je Zwischenstufe
Config.SUBTIER_COST_SHARE = 0.35 -- Anteil des naechsten Tier-Preises je Stufe
Config.SUBTIER_TIME_SHARE = 0.5 -- Reparaturzeit im Verhaeltnis zur Tier-Zeit
Config.SUBTIER_MIN_TIME = 4
Config.SUBTIER_TOP_COST_MULT = 2.5 -- auf der hoechsten Stufe gibt es keinen Sprung mehr

-- Reparatur-Minispiel ------------------------------------------------------
-- Wer an der Werkbank stehen bleibt, kann den Timer verkuerzen. Wer weggeht,
-- verliert nichts - der Timer laeuft wie bisher ab. Belohnen, nicht bestrafen.
--
-- Der Marker laeuft als Dreieckswelle ueber Util.RepairMarker und haengt nur an
-- Workspace:GetServerTimeNow(). Damit rechnen Client und Server dieselbe
-- Position aus, ohne dass ein Startzeitpunkt uebertragen werden muss.
Config.REPAIR_MINIGAME_ROUNDS = 3
Config.REPAIR_HIT_REDUCTION = 0.12 -- Anteil der RESTzeit je Treffer
Config.REPAIR_PERFECT_BONUS = 0.08 -- zusaetzlich, wenn der Kern getroffen wird
Config.REPAIR_MINIGAME_RANGE = 18 -- Studs zur Werkbank, sonst zaehlt der Klick nicht
Config.REPAIR_SWEEP = 1.8 -- Sekunden fuer einen kompletten Hin- und Rueckweg
Config.REPAIR_ZONE_HALF = 0.20 -- halbe Breite der gruenen Zone (0..1 um die Mitte)
Config.REPAIR_PERFECT_HALF = 0.07 -- halbe Breite des Kerns
-- Wie weit die vom Client gemeldete Position von der serverseitig berechneten
-- abweichen darf. Das ist der Lag-Ausgleich: innerhalb dieser Spanne zaehlt die
-- Client-Angabe, ausserhalb rechnet der Server mit seinem eigenen Wert weiter.
-- Luegen bringt also nichts, hoher Ping kostet aber auch nichts.
Config.REPAIR_LATENCY_TOLERANCE = 0.18
Config.REPAIR_TICK_COOLDOWN = 0.35

-- Rebirth ------------------------------------------------------------------
Config.REBIRTH_MULT = 0.25 -- +25 % Rate je Rebirth, dauerhaft
Config.REBIRTH_EXTRA_SLOT_AT = 1 -- ab diesem Rebirth ein zusaetzlicher Stellplatz
Config.REBIRTH_PAINT_AT = 3 -- ab hier exklusiver Lack

-- Was jeder Rebirth AUFMACHT. Der Multiplikator laeuft zusaetzlich weiter, aber
-- der Grund fuer den naechsten Durchgang ist ab v8 eine neue Faehigkeit und
-- keine groessere Zahl. Als Tabelle, damit im Code nirgends `if rebirths >= 4`
-- steht und das Menue vorab anzeigen kann, was als Naechstes kommt.
--
-- Jeder Eintrag: label = was im Menue steht, plus die Felder, die der Server
-- ausliest. Wer eine Freischaltung ergaenzt, ergaenzt sie HIER und liest sie
-- ueber ProfileOps.Unlocks aus.
Config.REBIRTH_UNLOCKS = {
	{ label = "Ein zusaetzlicher Stellplatz", extraCarSlot = true },
	{ label = "Hehler zahlt besser", fenceRate = 0.85 },
	{ label = "Exklusiver Lack auf Stufe 4", exclusivePaint = true },
	{ label = "Nachtschicht: ein langes Fenster pro Sitzung", nightShift = true },
	-- Der zweite Plot fehlt bewusst: dafuer muesste das View-Modell von
	-- "ein Plot je Spieler" auf "mehrere" umgestellt werden (GarageService,
	-- Snapshot, GarageView, DerelictService). Das ist ein eigener Auftrag und
	-- nichts, was man ohne Studio-Test einbaut.
}

-- Nachtschicht: einmal je Serverlauf laeuft ein Fenster laenger und die Beute
-- ist mehr wert. Ausgeloest vom HeistService, sobald ein Spieler mit der
-- Freischaltung im Server ist.
Config.NIGHT_SHIFT_WINDOW = 150 -- statt HEIST_WINDOW
Config.NIGHT_SHIFT_VALUE_MULT = 1.5 -- Leerstand-Teile sind in dieser Nacht mehr wert
-- Rebirth verlangt "alles auf der hoechsten Stufe". Bis v7 war das T4. Seit T4
-- nur noch Beute ist, haenge das an MAX_PURCHASABLE_TIER: sonst braeuchte ein
-- Rebirth bis zu 16 geklaute Prototypen, bei einem T4 pro
-- DERELICT_T4_COOLDOWN also Stunden - der Rebirth-Loop waere praktisch tot.
-- Wer die alte Haerte will, setzt hier 4.
Config.REBIRTH_REQUIRED_TIER = 3

-- Speichern ----------------------------------------------------------------
Config.AUTOSAVE_INTERVAL = 60
Config.DATASTORE_NAME = "GarageHeist_Profiles_v1"
Config.SESSION_LOCK_TIMEOUT = 90 -- danach gilt ein Lock als verwaist
Config.LOAD_ATTEMPTS = 6
Config.RETRY_BASE_WAIT = 2
-- Harte Obergrenze ueber ALLE Versuche zusammen. Danach wird gekickt statt den
-- Spieler minutenlang vor einer leeren Oberflaeche warten zu lassen.
Config.LOAD_TOTAL_BUDGET = 45

-- Klau-Fenster -------------------------------------------------------------
-- Takt: 3,5 Minuten Zyklus mit 75s offenem Fenster = rund ein Drittel Spielzeit
-- im Heist statt vorher einem Achtel. Das erste Fenster faellt in die erste
-- Session, nicht daneben.
Config.HEIST_INTERVAL = 210
Config.HEIST_WINDOW = 75
Config.HEIST_FIRST_DELAY = 45
Config.HEIST_WARN_AT = { 45, 15, 5 } -- Vorwarnungen in Sekunden vor Fensteroeffnung
Config.HEIST_PULSE_AT = 15 -- ab hier pulsiert die HUD-Anzeige
Config.DISMOUNT_TIME = 4 -- Sekunden Abmontieren
Config.DISMOUNT_MAX_DISTANCE = 16 -- bricht ab, wenn der Dieb weiter weg ist
Config.TACKLE_RANGE = 12
Config.TACKLE_COOLDOWN = 4
Config.TACKLE_SHAKE = 1.6 -- Staerke des Kamera-Wacklers beim Treffer
Config.CARRY_WALKSPEED = 12
-- Zwei Teile gleichzeitig sind moeglich, aber teuer: jedes weitere kostet
-- Tempo, und ein Rempler wirft ALLE auf einmal aus der Hand. Gier gegen Risiko.
Config.CARRY_MAX_PARTS = 2
Config.CARRY_SECOND_PENALTY = 2 -- Studs/s weniger je zusaetzlich getragenem Teil
-- Ohne diese Spanne ist ein Traeger (12) gegen einen Verfolger (16) chancenlos:
-- der Verfolger braucht nur alle TACKLE_COOLDOWN Sekunden erneut zu druecken.
-- Der Wert ist geraten und gehoert im Playtest gemessen.
Config.TACKLE_IMMUNITY = 3

-- Alarm --------------------------------------------------------------------
-- Jedes Teil, das in derselben Garage abmontiert wird, hebt deren Alarmstufe.
-- Der Zustand lebt nur waehrend des Fensters und steht NICHT im Profil.
-- Stufe 1: der Besitzer bekommt die Richtung. Stufe 2: die Position.
-- Stufe 3: alle im Server sehen es.
Config.ALARM_STEPS = { 1, 2, 4 } -- abmontierte Teile, ab denen die jeweilige Stufe gilt
Config.ALARM_DECAY = 25 -- Sekunden ohne neuen Diebstahl, bis eine Stufe faellt

-- Hehler -------------------------------------------------------------------
-- Abgabepunkt mitten im Hof. Sofort Cash statt das Teil selbst - die
-- Entscheidung auf dem Rueckweg, besonders mit einem Prototyp in der Hand.
Config.FENCE_RATE = 0.7
Config.FENCE_POSITION = Vector3.new(0, 0, 0)
Config.FENCE_COOLDOWN = 0.5
Config.NORMAL_WALKSPEED = 16
Config.DROPPED_PART_PICKUP_DISTANCE = 8
Config.GARAGE_LOCK_WINDOW = 20 -- Gamepass: eigenes Tor faellt nach 20s wieder zu

-- Leerstand-Garagen --------------------------------------------------------
-- Freie Plots werden waehrend des Fensters zu Zielen, damit der Heist auch bei
-- einem einzigen Spieler im Server stattfindet.
Config.DERELICT_VALUE_MULT = 0.6 -- Leerstand-Teile bringen weniger als geklaute Spielerteile
Config.DERELICT_MIN_PARTS = 1
Config.DERELICT_MAX_PARTS = 4
Config.DERELICT_MAX_TIER = 4 -- seit v8 auch T4, aber nur ueber die Schranken unten
-- Ab welchem Median-Garagenwert der anwesenden Spieler welche Stufe auftaucht.
Config.DERELICT_TIER_STEPS = { 0, 8000, 40000, 150000 }
-- T4 im Leerstand haengt an drei Schranken, damit daraus keine Farm wird:
-- oberste Stufe von DERELICT_TIER_STEPS erreicht, Cooldown abgelaufen, Wurf
-- gewonnen. Und dann liegt hoechstens EIN Prototyp im ganzen Server, in genau
-- einer Box. Der Cooldown laeuft in Serverzeit - Rejoin hilft nicht.
Config.DERELICT_T4_CHANCE = 0.35
Config.DERELICT_T4_COOLDOWN = 600

-- Plots --------------------------------------------------------------------
Config.PLOT_COUNT = 12
Config.PLOT_WIDTH = 46
Config.PLOT_DEPTH = 54
Config.PLOT_HEIGHT = 18
Config.PLOTS_PER_ROW = 6
Config.PLOT_GAP = 10
Config.ROW_GAP = 110
Config.BASE_HEIGHT = 0

-- Garagen-Stufen -----------------------------------------------------------
Config.GARAGE_LEVELS = {
	{ cost = 0, rateMult = 1.00, carSlots = 1, label = "Blechbude" },
	{ cost = 2500, rateMult = 1.15, carSlots = 2, label = "Werkstatt" },
	{ cost = 14000, rateMult = 1.35, carSlots = 2, label = "Tuning-Shop" },
	{ cost = 65000, rateMult = 1.60, carSlots = 3, label = "Rennstall" },
	{ cost = 260000, rateMult = 2.00, carSlots = 4, label = "Werk" },
}

-- Monetarisierung ----------------------------------------------------------
Config.VIP_RATE_MULT = 2.0
-- Bewusst so gewaehlt, dass auch das groesste Paket den Loop nicht ersetzt:
-- das teuerste Garagen-Upgrade kostet 260k, der Supersportler 75k.
Config.CASH_PACKS = {
	CashSmall = 5000,
	CashMedium = 30000,
	CashLarge = 150000,
}
Config.RADAR_TOP_COUNT = 5

-- Daily Reward -------------------------------------------------------------
Config.DAILY_REWARDS = { 250, 500, 900, 1500, 2600, 4200, 8000 }

-- Admin -------------------------------------------------------------------
-- Der Besitzer des Spiels ist automatisch Admin, ohne Eintrag. In Studio ist
-- jeder Admin (eigener Rechner). Hier kommen nur zusaetzliche Tester rein -
-- UserId, nicht Benutzername.
Config.ADMIN_USER_IDS = {}

-- Badges -------------------------------------------------------------------
-- Platzhalter. Im Creator Dashboard anlegen und hier eintragen, siehe
-- docs/SETUP.md. Solange 0 drinsteht, wird kein Badge vergeben.
Config.BADGE_IDS = {
	FirstSteal = 0, -- erstes abgeliefertes Diebesgut
	Rich = 0, -- 100.000 Cash auf dem Konto
	FirstRebirth = 0, -- erster Rebirth
}
Config.BADGE_RICH_AT = 100000

-- Leaderboard --------------------------------------------------------------
Config.LEADERBOARD_REFRESH = 5

return Config
