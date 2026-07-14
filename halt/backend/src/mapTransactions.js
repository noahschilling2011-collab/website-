// Map a bank provider's transaction shape to HALT's internal Transaction.
//
// GoCardless Bank Account Data (and most PSD2 AIS providers) return "booked"
// transactions with a signed amount: negative = money leaving the account.
// HALT's engine uses positive = outgoing, so we flip the sign.
//
// Category is inferred heuristically from the counterparty name / remittance
// text, because PSD2 feeds rarely carry a reliable merchant category. The
// high-risk keywords are what actually drive escalation, so we detect those well
// and leave everything else as a neutral category.

const KEYWORDS = [
  { cat: 'crypto', re: /\b(bitcoin|crypto|coin|binance|kraken|coinbase|bitpanda|wallet|bit\s?trade|blockchain)\b/i },
  { cat: 'precious_metals', re: /\b(gold|silber|edelmetall|philoro|degussa|bullion|precious\s?metal)\b/i },
  { cat: 'gift_card', re: /\b(gift\s?card|geschenkkarte|guthabenkarte|steam|google\s?play|itunes|amazon\s?card|paysafe)\b/i },
  { cat: 'money_remittance', re: /\b(western\s?union|moneygram|ria|remit|wise|transfer\s?service)\b/i },
  { cat: 'cash_withdrawal', re: /\b(atm|geldautomat|bargeld|cash|abhebung|withdrawal)\b/i },
  { cat: 'groceries', re: /\b(rewe|edeka|aldi|lidl|kaufland|penny|netto|supermarkt)\b/i },
  { cat: 'utilities', re: /\b(stadtwerke|strom|gas|wasser|telekom|vodafone|versicherung)\b/i },
];

export function inferCategory(name = '', remittance = '', proprietaryCode = '') {
  const hay = `${name} ${remittance} ${proprietaryCode}`;
  for (const { cat, re } of KEYWORDS) {
    if (re.test(hay)) return cat;
  }
  return 'transfer';
}

/** Map one GoCardless booked transaction to a HALT Transaction. */
export function mapGoCardlessTransaction(gc, idx = 0) {
  const raw = Number.parseFloat(gc?.transactionAmount?.amount ?? '0');
  // GoCardless: debit is negative. HALT: outgoing is positive → flip sign.
  const amount = -raw;
  const payeeName =
    gc.creditorName ||
    gc.debtorName ||
    gc.remittanceInformationUnstructured ||
    (Array.isArray(gc.remittanceInformationUnstructuredArray)
      ? gc.remittanceInformationUnstructuredArray.join(' ')
      : '') ||
    'Unbekannt';
  const payeeIban = gc.creditorAccount?.iban || gc.debtorAccount?.iban || '';
  const remittance =
    gc.remittanceInformationUnstructured ||
    (Array.isArray(gc.remittanceInformationUnstructuredArray)
      ? gc.remittanceInformationUnstructuredArray.join(' ')
      : '');
  const date = gc.bookingDate || gc.valueDate || gc.bookingDateTime || new Date().toISOString();

  return {
    id: gc.transactionId || gc.internalTransactionId || `gc_${idx}`,
    date: new Date(date).toISOString(),
    amount,
    payeeName,
    payeeIban,
    category: inferCategory(payeeName, remittance, gc.proprietaryBankTransactionCode),
    channel: 'sepa',
  };
}

/** Map a GoCardless /transactions/ response (booked list) to HALT transactions. */
export function mapGoCardlessResponse(body) {
  const booked = body?.transactions?.booked ?? [];
  return booked.map((t, i) => mapGoCardlessTransaction(t, i));
}
