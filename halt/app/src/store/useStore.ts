// App state. Zustand keeps this lean — no Redux ceremony for an MVP.
// Persistence to disk (AsyncStorage) is a one-line middleware add later.

import { create } from 'zustand';
import type {
  Transaction,
  Assessment,
  ProtectedPerson,
  TrustedContact,
} from '../types';
import { assessFeed } from '../lib/ruleEngine';
import { connectBank, fetchTransactions } from '../lib/mockBank';
import { alertSummary, placeEscalationCall, sendPush } from '../lib/escalation';

export interface AlertRecord {
  assessment: Assessment;
  transaction: Transaction;
  summary: string;
  createdAt: string;
  /** Set once the trusted person taps "Ich kümmere mich" / "Alles ok". */
  resolution?: 'handled' | 'dismissed';
}

interface AppState {
  person: ProtectedPerson | null;
  contacts: TrustedContact[];
  transactions: Transaction[];
  assessments: Assessment[];
  alerts: AlertRecord[];
  loading: boolean;

  setPerson: (name: string) => void;
  addContact: (c: Omit<TrustedContact, 'id'>) => void;
  removeContact: (id: string) => void;

  /** Runs the full flow: connect → fetch → assess → escalate alerts. */
  connectAndScan: (now?: string) => Promise<void>;
  resolveAlert: (transactionId: string, resolution: 'handled' | 'dismissed') => void;
}

let idCounter = 0;
const nextId = () => `id_${++idCounter}`;

export const useStore = create<AppState>((set, get) => ({
  person: null,
  contacts: [],
  transactions: [],
  assessments: [],
  alerts: [],
  loading: false,

  setPerson: (name) =>
    set({ person: { id: nextId(), name, bankConnected: false } }),

  addContact: (c) =>
    set((s) => ({ contacts: [...s.contacts, { ...c, id: nextId() }] })),

  removeContact: (id) =>
    set((s) => ({ contacts: s.contacts.filter((c) => c.id !== id) })),

  connectAndScan: async (now = new Date().toISOString()) => {
    set({ loading: true });
    try {
      await connectBank();
      const transactions = await fetchTransactions();
      const assessments = assessFeed(transactions);

      // Build alert records for anything the engine says to escalate.
      const txById = new Map(transactions.map((t) => [t.id, t]));
      const newAlerts: AlertRecord[] = assessments
        .filter((a) => a.shouldEscalate)
        .map((a) => {
          const tx = txById.get(a.transactionId)!;
          return { assessment: a, transaction: tx, summary: alertSummary(tx, a), createdAt: now };
        });

      // Fire the (stubbed) outbound channels for each fresh alert.
      const contacts = get().contacts;
      for (const alert of newAlerts) {
        for (const contact of contacts) {
          await sendPush(contact, alert.summary, now);
          if (alert.assessment.level === 'alert') {
            await placeEscalationCall(contact, alert.transaction, alert.assessment, now);
          }
        }
      }

      set((s) => ({
        transactions,
        assessments,
        alerts: newAlerts,
        person: s.person ? { ...s.person, bankConnected: true } : s.person,
      }));
    } finally {
      set({ loading: false });
    }
  },

  resolveAlert: (transactionId, resolution) =>
    set((s) => ({
      alerts: s.alerts.map((a) =>
        a.transaction.id === transactionId ? { ...a, resolution } : a,
      ),
    })),
}));
