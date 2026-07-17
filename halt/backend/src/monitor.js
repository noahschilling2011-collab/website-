// Continuous monitoring — the actual product promise.
//
// The backend periodically scans every user's connected account BY ITSELF and
// escalates fresh alerts to their verified contact. The victim never has to
// open an app; the trigger hangs on the money, not on anyone's doubt.
//
// Rate-limit reality (GoCardless free tier): roughly 4 transaction reads per
// account per day. So the monitor ticks conservatively (default every 6h) and
// the per-user seen-store dedupes, so nobody is ever alerted twice for the
// same movement. All deps are injected, so every path is testable.

export function createMonitor({
  userData,
  gc,
  sender,
  mapResponse,
  runScan,
  channel = 'both',
  fallbackPhone = null,
  intervalMs = 6 * 3600 * 1000,
  log = () => {},
}) {
  let timer = null;
  let running = false;
  let lastRunAt = null;
  let lastResult = null;

  async function tick(now = Date.now()) {
    if (running) return lastResult; // never overlap two sweeps
    running = true;
    const stats = { users: 0, scanned: 0, alertsDelivered: 0, errors: [] };
    try {
      for (const uid of userData.userIds()) {
        const reqId = userData.getRequisition(uid);
        if (!reqId) continue; // no bank connected — nothing to watch
        stats.users += 1;
        try {
          const requisition = await gc.getRequisition(reqId);
          for (const accountId of requisition.accounts || []) {
            const raw = await gc.getTransactions(accountId);
            const transactions = mapResponse(raw);
            const result = await runScan(transactions, {
              sender,
              seen: userData.seenStore(uid),
              to: userData.alertPhone(uid) || fallbackPhone,
              channel,
            });
            userData.setAlerts(uid, result.alerts);
            stats.scanned += 1;
            stats.alertsDelivered += result.newlyDelivered;
            if (result.newlyDelivered > 0) {
              log(`[monitor] ${uid}: ${result.newlyDelivered} neue Alarme eskaliert`);
            }
          }
        } catch (e) {
          // One user's broken bank link must never stop the sweep for everyone else.
          stats.errors.push({ uid, message: e.message });
          log(`[monitor] Fehler bei ${uid}: ${e.message}`);
        }
      }
      lastRunAt = now;
      lastResult = stats;
      return stats;
    } finally {
      running = false;
    }
  }

  function start() {
    if (timer) return;
    // First sweep shortly after boot (Render restarts shouldn't burn API quota
    // instantly), then on the conservative interval.
    const first = setTimeout(() => { tick().catch(() => {}); }, 60 * 1000);
    first.unref?.();
    timer = setInterval(() => { tick().catch(() => {}); }, intervalMs);
    timer.unref?.();
  }

  function stop() {
    if (timer) clearInterval(timer);
    timer = null;
  }

  function status() {
    return {
      enabled: Boolean(timer),
      intervalHours: Math.round((intervalMs / 3600000) * 10) / 10,
      lastRunAt,
      lastResult,
    };
  }

  return { tick, start, stop, status };
}
