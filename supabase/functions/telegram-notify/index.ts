// Database Webhook (in_app_notifications INSERT) → Telegram mesajı
// Gizli açarlar (Edge Functions → Secrets): TELEGRAM_BOT_TOKEN, WEBHOOK_SECRET, SITE_URL
// SUPABASE_URL və SUPABASE_SERVICE_ROLE_KEY avtomatik verilir.

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// Hansı bildirişlər Telegram-a getsin (qalanları yalnız tətbiqdə görünür)
const SEND_KINDS = new Set([
  'new_request',
  'bid_accepted',
  'bid_lost',
  'deal_failed',
  'payment_order',
  'report',
  'suspended',
  'payment_confirmed',
]);

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

Deno.serve(async (req) => {
  const secret = Deno.env.get('WEBHOOK_SECRET');
  if (!secret || req.headers.get('x-webhook-secret') !== secret) {
    return new Response('unauthorized', { status: 401 });
  }

  const token = Deno.env.get('TELEGRAM_BOT_TOKEN');
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!token || !url || !key) return new Response('not configured', { status: 500 });

  let payload: { type?: string; record?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return new Response('bad request', { status: 400 });
  }
  const rec = payload.record;
  if (payload.type !== 'INSERT' || !rec) return new Response('ignored', { status: 200 });

  const kind = String(rec.kind ?? '');
  const userId = String(rec.user_id ?? '');
  if (!SEND_KINDS.has(kind) || !/^[0-9a-f-]{36}$/i.test(userId)) return new Response('skipped', { status: 200 });

  const lookup = await fetch(`${url}/rest/v1/telegram_links?user_id=eq.${userId}&select=chat_id`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!lookup.ok) return new Response('lookup failed', { status: 200 });
  const rows = (await lookup.json()) as { chat_id: number | null }[];
  const chatId = rows[0]?.chat_id;
  if (!chatId) return new Response('no telegram', { status: 200 });

  const site = Deno.env.get('SITE_URL') ?? '';
  const title = esc(String(rec.title ?? ''));
  const body = rec.body ? esc(String(rec.body)) : '';
  const emoji =
    kind === 'new_request' ? '🔔' : kind === 'bid_accepted' ? '🎉' : kind === 'payment_confirmed' ? '✅' : 'ℹ️';
  const text = `${emoji} <b>${title}</b>${body ? `\n${body}` : ''}${site ? `\n\n${esc(site)}` : ''}`;

  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ chat_id: chatId, text, parse_mode: 'HTML', disable_web_page_preview: true }),
  });

  // İstifadəçi botu bloklayıbsa əlaqəni təmizlə
  if (res.status === 403) {
    await fetch(`${url}/rest/v1/telegram_links?user_id=eq.${userId}`, {
      method: 'PATCH',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: null, linked_at: null }),
    });
  }
  return new Response('ok', { status: 200 });
});
