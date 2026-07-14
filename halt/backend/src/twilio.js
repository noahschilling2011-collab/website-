// Twilio: send a real SMS and place a real voice call, via the REST API with
// plain fetch (no SDK). Verified against current Twilio docs.
//
// SMS:  POST https://api.twilio.com/2010-04-01/Accounts/{Sid}/Messages.json
// Call: POST .../Calls.json  (inline TwiML via the `Twiml` param — no webhook needed)
// Auth: HTTP Basic, username = Account SID, password = Auth Token.
//
// Trial accounts can only reach VERIFIED numbers, and `From` must be your Twilio
// number — see backend/README.md.

const apiBase = (sid) => `https://api.twilio.com/2010-04-01/Accounts/${sid}`;

function escapeXml(s) {
  return String(s).replace(/[<>&'"]/g, (c) => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', "'": '&apos;', '"': '&quot;' }[c]));
}

/** Returns a sender { sms(to, body), call(to, message) } that really calls Twilio. */
export function twilioSender({ accountSid, authToken, from }) {
  const base = apiBase(accountSid);
  const auth = 'Basic ' + Buffer.from(`${accountSid}:${authToken}`).toString('base64');

  async function post(resource, params) {
    const res = await fetch(`${base}/${resource}`, {
      method: 'POST',
      headers: { Authorization: auth, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams(params),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new Error(`Twilio ${resource} ${res.status}: ${data.message || 'error'} (code ${data.code ?? '?'})`);
    }
    return data.sid;
  }

  return {
    sms: (to, body) => post('Messages.json', { To: to, From: from, Body: body }),
    call: (to, message) =>
      post('Calls.json', {
        To: to,
        From: from,
        Twiml: `<Response><Say language="de-DE">${escapeXml(message)}</Say></Response>`,
      }),
  };
}

/** No-credentials fallback: logs what it would send. Keeps everything runnable. */
export function dryRunSender() {
  return {
    sms: async (to, body) => {
      console.log(`[DRY_RUN] 📱 SMS → ${to}: ${body}`);
      return 'DRYRUN_SMS';
    },
    call: async (to, message) => {
      console.log(`[DRY_RUN] ☎️  CALL → ${to}: "${message}"`);
      return 'DRYRUN_CALL';
    },
  };
}
