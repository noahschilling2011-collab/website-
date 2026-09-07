CREATE TABLE "anhaenge" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"nachricht_id" uuid NOT NULL,
	"dateiname" text NOT NULL,
	"mime_typ" text NOT NULL,
	"groesse_bytes" integer NOT NULL,
	"text_extrakt" text,
	"extraktion_fehlgeschlagen" boolean DEFAULT false NOT NULL
);
--> statement-breakpoint
CREATE TABLE "anmelde_tokens" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"token_hash" text NOT NULL,
	"gueltig_bis" timestamp with time zone NOT NULL,
	"eingeloest_am" timestamp with time zone,
	CONSTRAINT "anmelde_tokens_token_hash_unique" UNIQUE("token_hash")
);
--> statement-breakpoint
CREATE TABLE "ausgang" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"vorgang_id" uuid NOT NULL,
	"an" text NOT NULL,
	"betreff" text NOT NULL,
	"text" text NOT NULL,
	"ical_methode" text,
	"ical_inhalt" text,
	"in_reply_to" text,
	"referenzen" text,
	"halten_bis" timestamp with time zone NOT NULL,
	"status" text DEFAULT 'gehalten' NOT NULL,
	"gesendet_am" timestamp with time zone,
	"message_id" text,
	"fehler" text,
	"erstellt_am" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "calendar_connections" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"nutzer_id" uuid NOT NULL,
	"kind" text NOT NULL,
	"secret_ref" text NOT NULL,
	"konfig" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"last_ok_at" timestamp with time zone,
	"last_error" text,
	"last_error_at" timestamp with time zone,
	"erstellt_am" timestamp with time zone DEFAULT now() NOT NULL,
	"widerrufen_am" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "nachrichten" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"vorgang_id" uuid NOT NULL,
	"richtung" text NOT NULL,
	"message_id" text,
	"in_reply_to" text,
	"referenzen" text,
	"von" text NOT NULL,
	"an" text NOT NULL,
	"betreff" text NOT NULL,
	"text" text NOT NULL,
	"zeitpunkt" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "nutzer" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"name" text,
	"zeitzone" text DEFAULT 'Europe/Berlin' NOT NULL,
	"handle" text NOT NULL,
	"arbeitszeiten" jsonb DEFAULT '{"1":[{"von":"08:00","bis":"17:00"}],"2":[{"von":"08:00","bis":"17:00"}],"3":[{"von":"08:00","bis":"17:00"}],"4":[{"von":"08:00","bis":"17:00"}]}'::jsonb NOT NULL,
	"abgeschlossene_vorgaenge" integer DEFAULT 0 NOT NULL,
	"zahlend_seit" timestamp with time zone,
	"erstellt_am" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "nutzer_email_unique" UNIQUE("email"),
	CONSTRAINT "nutzer_handle_unique" UNIQUE("handle")
);
--> statement-breakpoint
CREATE TABLE "protokoll" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"nutzer_id" uuid NOT NULL,
	"vorgang_id" uuid,
	"zeitpunkt" timestamp with time zone DEFAULT now() NOT NULL,
	"was" text NOT NULL,
	"details" text
);
--> statement-breakpoint
CREATE TABLE "regeln" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"nutzer_id" uuid NOT NULL,
	"empfaenger" text NOT NULL,
	"aktionstyp" text NOT NULL,
	"bestaetigte_sendungen" integer DEFAULT 0 NOT NULL,
	"automatisch" boolean DEFAULT false NOT NULL,
	"geaendert_am" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "termine" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"vorgang_id" uuid NOT NULL,
	"uid" text NOT NULL,
	"sequence" integer DEFAULT 0 NOT NULL,
	"titel" text NOT NULL,
	"von" timestamp with time zone NOT NULL,
	"bis" timestamp with time zone NOT NULL,
	"zeitzone" text NOT NULL,
	"ort" text,
	"platzierungs_status" text DEFAULT 'offen' NOT NULL,
	"platzierungs_art" text,
	"platzierungs_wert" text,
	"erstellt_am" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "termine_uid_unique" UNIQUE("uid")
);
--> statement-breakpoint
CREATE TABLE "vorgaenge" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"nutzer_id" uuid NOT NULL,
	"art" text NOT NULL,
	"zustand" text DEFAULT 'neu' NOT NULL,
	"titel" text NOT NULL,
	"gegenueber_email" text,
	"gegenueber_name" text,
	"thread_key" text NOT NULL,
	"faellig_am" timestamp with time zone,
	"naechste_erinnerung" timestamp with time zone,
	"erinnerungen_gesendet" integer DEFAULT 0 NOT NULL,
	"erstellt_am" timestamp with time zone DEFAULT now() NOT NULL,
	"geaendert_am" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "anhaenge" ADD CONSTRAINT "anhaenge_nachricht_id_nachrichten_id_fk" FOREIGN KEY ("nachricht_id") REFERENCES "public"."nachrichten"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "ausgang" ADD CONSTRAINT "ausgang_vorgang_id_vorgaenge_id_fk" FOREIGN KEY ("vorgang_id") REFERENCES "public"."vorgaenge"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "calendar_connections" ADD CONSTRAINT "calendar_connections_nutzer_id_nutzer_id_fk" FOREIGN KEY ("nutzer_id") REFERENCES "public"."nutzer"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "nachrichten" ADD CONSTRAINT "nachrichten_vorgang_id_vorgaenge_id_fk" FOREIGN KEY ("vorgang_id") REFERENCES "public"."vorgaenge"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "protokoll" ADD CONSTRAINT "protokoll_nutzer_id_nutzer_id_fk" FOREIGN KEY ("nutzer_id") REFERENCES "public"."nutzer"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "regeln" ADD CONSTRAINT "regeln_nutzer_id_nutzer_id_fk" FOREIGN KEY ("nutzer_id") REFERENCES "public"."nutzer"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "termine" ADD CONSTRAINT "termine_vorgang_id_vorgaenge_id_fk" FOREIGN KEY ("vorgang_id") REFERENCES "public"."vorgaenge"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "vorgaenge" ADD CONSTRAINT "vorgaenge_nutzer_id_nutzer_id_fk" FOREIGN KEY ("nutzer_id") REFERENCES "public"."nutzer"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "ausgang_status_idx" ON "ausgang" USING btree ("status");--> statement-breakpoint
CREATE INDEX "cc_nutzer_idx" ON "calendar_connections" USING btree ("nutzer_id");--> statement-breakpoint
CREATE INDEX "nachricht_vorgang_idx" ON "nachrichten" USING btree ("vorgang_id");--> statement-breakpoint
CREATE INDEX "protokoll_nutzer_idx" ON "protokoll" USING btree ("nutzer_id");--> statement-breakpoint
CREATE UNIQUE INDEX "regel_unique" ON "regeln" USING btree ("nutzer_id","empfaenger","aktionstyp");--> statement-breakpoint
CREATE INDEX "termin_vorgang_idx" ON "termine" USING btree ("vorgang_id");--> statement-breakpoint
CREATE INDEX "vorgang_nutzer_idx" ON "vorgaenge" USING btree ("nutzer_id");--> statement-breakpoint
CREATE INDEX "vorgang_thread_idx" ON "vorgaenge" USING btree ("thread_key");