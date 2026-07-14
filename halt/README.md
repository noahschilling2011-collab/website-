# HALT — Landingpage (Demand-Test)

Eine einzelne, selbst-enthaltene HTML-Datei (`index.html`). Kein Build, kein Backend, keine Abhängigkeiten. Ziel: der €0-Test aus der Strategie — **klickt irgendjemand?**

## In 5 Minuten live

1. **E-Mail-Warteliste anschließen** (kostenlos): Konto bei [Formspree](https://formspree.io) oder [Buttondown](https://buttondown.email) anlegen, Endpunkt kopieren.
   - In `index.html` `https://formspree.io/f/DEIN_FORM_ID` durch deinen Endpunkt ersetzen.
2. **Zahlbereitschaft messen** (optional, aber der eigentliche Test): [Stripe Payment Link](https://stripe.com/de/payments/payment-links) anlegen (6 €/Monat, Abo).
   - `https://buy.stripe.com/DEIN_PAYMENT_LINK` in `index.html` ersetzen.
   - Hinweis: Stripe braucht einen geschäftsfähigen Kontoinhaber. Als 15-Jähriger brauchst du hier einen Erwachsenen als Träger (Eltern). Bis dahin reicht die Warteliste allein als Interessens-Signal.
3. **Deployen** (kostenlos):
   - **Netlify/Vercel:** Ordner `halt/` per Drag-and-drop hochladen — fertig.
   - **GitHub Pages:** Repo-Einstellungen → Pages → Branch wählen, `/halt` als Quelle (oder Datei ins Root verschieben).
   - **Lokal ansehen:** `index.html` einfach im Browser öffnen.

## Was gemessen wird

- **Warteliste-Eintrag** = „interessiert mich".
- **Klick auf den Zahl-Button** = „ich würde zahlen". Das ist die wertvollere Zahl.
- Klicks auf beide CTAs werden zusätzlich lokal in `localStorage` gezählt (Konsole: `[HALT] Klick: …`). Für echte Zahlen später [Plausible](https://plausible.io) o. Ä. einbauen — eine Zeile im `<head>`.

## Bewusst NICHT drin

- Keine erfundenen Nutzerzahlen, keine falschen Testimonials. Eine Pre-Launch-Seite, die lügt, verbrennt genau das Vertrauen, das der einzige echte Moat ist.
- Kein Produkt-Feature, das noch nicht existiert, wird als „live" dargestellt. Der Ehrlichkeits-Hinweis auf der Seite ist Absicht.

## Zielgruppe

Die Seite spricht **Angehörige** an (Tochter/Sohn/Enkel), nicht die gefährdete Person selbst — das ist der Kern der Strategie: Der Käufer ist nicht das Opfer.
