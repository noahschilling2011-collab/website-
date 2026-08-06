ALTER TABLE "anmelde_tokens" ADD COLUMN "code_hash" text;--> statement-breakpoint
ALTER TABLE "anmelde_tokens" ADD COLUMN "versuche" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "anmelde_tokens" ADD COLUMN "erstellt_am" timestamp with time zone DEFAULT now() NOT NULL;