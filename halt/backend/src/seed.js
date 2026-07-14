// Demo transaction history — the same seed as the app, including an ongoing
// crypto scam. Used by the /demo-scan endpoint so you can test the FULL alert
// path (engine → your phone rings) without connecting any bank.

export const SEED = [
  { id: 'h1', date: '2026-06-01T08:12:00Z', amount: 42.5, payeeName: 'REWE Markt', payeeIban: 'DE11111111111111111111', category: 'groceries', channel: 'card' },
  { id: 'h2', date: '2026-06-02T07:00:00Z', amount: 89.9, payeeName: 'Stadtwerke', payeeIban: 'DE22222222222222222222', category: 'utilities', channel: 'standing_order' },
  { id: 'h3', date: '2026-06-05T14:30:00Z', amount: 31.2, payeeName: 'Apotheke Sonne', payeeIban: 'DE33333333333333333333', category: 'retail', channel: 'card' },
  { id: 'h4', date: '2026-06-09T10:05:00Z', amount: 200, payeeName: 'Enkel Max', payeeIban: 'DE44444444444444444444', category: 'transfer', channel: 'sepa' },
  { id: 'h5', date: '2026-06-12T16:20:00Z', amount: 60, payeeName: 'ATM Sparkasse', payeeIban: 'DE55555555555555555555', category: 'cash_withdrawal', channel: 'atm' },
  { id: 'h6', date: '2026-06-18T09:45:00Z', amount: 54.1, payeeName: 'REWE Markt', payeeIban: 'DE11111111111111111111', category: 'groceries', channel: 'card' },
  { id: 'h7', date: '2026-06-25T11:00:00Z', amount: 75, payeeName: 'Friseur Schmidt', payeeIban: 'DE66666666666666666666', category: 'retail', channel: 'card' },
  { id: 's1', date: '2026-07-11T13:10:00Z', amount: 480, payeeName: 'BitTrade Ltd', payeeIban: 'LT991111222233334444', category: 'crypto', channel: 'instant' },
  { id: 's2', date: '2026-07-12T15:40:00Z', amount: 1500, payeeName: 'BitTrade Ltd', payeeIban: 'LT991111222233334444', category: 'crypto', channel: 'instant' },
  { id: 's3', date: '2026-07-13T09:20:00Z', amount: 3200, payeeName: 'Secure Wallet SA', payeeIban: 'ES881111222233334444', category: 'crypto', channel: 'instant' },
];
