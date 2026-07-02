/**
 * GraphQL read layer over the same services as the REST API.
 * Mutations stay in REST (single write path); GraphQL is optimized for
 * flexible dashboard/mobile reads.
 */
import { createSchema } from 'graphql-yoga';
import { query } from '../db/pool.js';
import type { AuthUser } from '../middleware/auth.js';

export interface GqlContext {
  user: AuthUser | null;
}

const typeDefs = /* GraphQL */ `
  type User {
    id: ID!
    email: String!
    displayName: String!
    role: String!
  }

  type Conversation {
    id: ID!
    title: String!
    provider: String!
    updatedAt: String!
  }

  type Task {
    id: ID!
    title: String!
    status: String!
    priority: Int!
    dueAt: String
  }

  type Note {
    id: ID!
    title: String!
    content: String!
    pinned: Boolean!
    updatedAt: String!
  }

  type CalendarEvent {
    id: ID!
    title: String!
    startsAt: String!
    endsAt: String!
    allDay: Boolean!
  }

  type Query {
    me: User
    conversations(limit: Int = 20): [Conversation!]!
    tasks(status: String): [Task!]!
    notes(search: String): [Note!]!
    events(from: String, to: String): [CalendarEvent!]!
  }
`;

function requireUser(ctx: GqlContext): AuthUser {
  if (!ctx.user) throw new Error('Not authenticated');
  return ctx.user;
}

export const schema = createSchema<GqlContext>({
  typeDefs,
  resolvers: {
    Query: {
      me: async (_p, _a, ctx) => {
        const user = requireUser(ctx);
        const rows = await query(
          'SELECT id, email, display_name AS "displayName", role FROM users WHERE id = $1',
          [user.id],
        );
        return rows[0] ?? null;
      },
      conversations: async (_p, args: { limit: number }, ctx) => {
        const user = requireUser(ctx);
        return query(
          `SELECT id, title, provider, updated_at AS "updatedAt"
           FROM conversations WHERE user_id = $1 ORDER BY updated_at DESC LIMIT $2`,
          [user.id, Math.min(args.limit, 100)],
        );
      },
      tasks: async (_p, args: { status?: string }, ctx) => {
        const user = requireUser(ctx);
        return query(
          `SELECT id, title, status, priority, due_at AS "dueAt"
           FROM tasks WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
           ORDER BY priority DESC, created_at DESC LIMIT 500`,
          [user.id, args.status ?? null],
        );
      },
      notes: async (_p, args: { search?: string }, ctx) => {
        const user = requireUser(ctx);
        return query(
          `SELECT id, title, content, pinned, updated_at AS "updatedAt"
           FROM notes WHERE user_id = $1
             AND ($2::text IS NULL OR title ILIKE '%' || $2 || '%')
           ORDER BY pinned DESC, updated_at DESC LIMIT 500`,
          [user.id, args.search ?? null],
        );
      },
      events: async (_p, args: { from?: string; to?: string }, ctx) => {
        const user = requireUser(ctx);
        return query(
          `SELECT id, title, starts_at AS "startsAt", ends_at AS "endsAt", all_day AS "allDay"
           FROM calendar_events WHERE user_id = $1
             AND ($2::timestamptz IS NULL OR ends_at >= $2)
             AND ($3::timestamptz IS NULL OR starts_at <= $3)
           ORDER BY starts_at LIMIT 1000`,
          [user.id, args.from ?? null, args.to ?? null],
        );
      },
    },
  },
});
