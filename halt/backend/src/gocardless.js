// GoCardless Bank Account Data (formerly Nordigen) — real PSD2 account access on
// the free tier. Verified against current docs.
//
// Host:  https://bankaccountdata.gocardless.com/api/v2   (NOT api.gocardless.com)
// Auth:  POST secret_id/secret_key -> {access, refresh}; then Bearer <access>.
// Flow:  createRequisition -> user opens `link` and consents -> getRequisition
//        returns account ids -> getTransactions.
//
// For safe testing use the sandbox institution SANDBOXFINANCE_SFIN0000: real
// OAuth flow, fake data, and you can type any value on the consent screen.

const BASE = 'https://bankaccountdata.gocardless.com/api/v2';

export function createGoCardlessClient({ secretId, secretKey }) {
  let access = null;
  let accessExpiresAt = 0;

  async function getToken() {
    if (access && Date.now() < accessExpiresAt) return access;
    const res = await fetch(`${BASE}/token/new/`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({ secret_id: secretId, secret_key: secretKey }),
    });
    const d = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`GoCardless token ${res.status}: ${JSON.stringify(d)}`);
    access = d.access;
    accessExpiresAt = Date.now() + ((d.access_expires ?? 86400) * 1000) - 60_000;
    return access;
  }

  async function api(path, { method = 'GET', body } = {}) {
    const token = await getToken();
    const res = await fetch(`${BASE}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/json',
        ...(body ? { 'Content-Type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const d = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(`GoCardless ${method} ${path} ${res.status}: ${JSON.stringify(d)}`);
    return d;
  }

  return {
    listInstitutions: (country = 'DE') => api(`/institutions/?country=${encodeURIComponent(country)}`),

    // Returns { id, link, status }. Send the user to `link` to grant consent.
    // `reference` must be unique per requisition, so default to a fresh one.
    createRequisition: ({ institutionId, redirect, reference }) =>
      api('/requisitions/', {
        method: 'POST',
        body: {
          redirect,
          institution_id: institutionId,
          reference: reference || `halt-${Date.now()}-${Math.floor(Math.random() * 1e6)}`,
          user_language: 'DE',
        },
      }),

    // After consent, status becomes "LN" and `accounts` is populated.
    getRequisition: (requisitionId) => api(`/requisitions/${requisitionId}/`),

    // Raw provider transactions: { transactions: { booked: [...], pending: [...] } }
    getTransactions: (accountId) => api(`/accounts/${accountId}/transactions/`),
  };
}
