// Telegram → bot mesajları. /start KOD ilə hesab bağlanır, /stop ilə ayrılır.
// Gizli açarlar: TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET (SUPABASE_URL / SERVICE_ROLE avtomatik)

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

type Update = { message?: { text?: string; chat?: { id: number; type?: string } } };

Deno.serve(async (req) => {
  const secret = Deno.env.get('TELEGRAM_WEBHOOK_SECRET');
  if (!secret || req.headers.get('x-telegram-bot-api-secret-token') !== secret) {
    return new Response('unauthorized', { status: 401 });
  }
  const token = Deno.env.get('TELEGRAM_BOT_TOKEN');
  const url = Deno.env.get('SUPABASE_URL');
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!token || !url || !key) return new Response('not configured', { status: 500 });

  let update: Update;
  try {
    update = await req.json();
  } catch {
    return new Response('bad request', { status: 400 });
  }
  const msg = update.message;
  const chatId = msg?.chat?.id;
  const text = (msg?.text ?? '').trim();
  if (!chatId || msg?.chat?.type !== 'private') return new Response('ok');

  const reply = (t: string) =>
    fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text: t }),
    });

  const m = /^\/start(?:@\w+)?\s+([A-Za-z0-9]{6,20})$/.exec(text);
  if (m) {
    const r = await fetch(`${url}/rest/v1/rpc/telegram_complete_link`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_code: m[1], p_chat_id: chatId }),
    });
    const ok = r.ok && (await r.json()) === true;
    await reply(
      ok
        ? '✅ AutoTender hesabınız bağlandı. Yeni sorğular və təklif nəticələri burada görünəcək. Ayırmaq üçün /stop yazın.'
        : '❌ Kod yanlışdır və ya vaxtı bitib. AutoTender-də "Hesab" bölməsindən yeni kod alın.'
    );
  } else if (/^\/stop/.test(text)) {
    await fetch(`${url}/rest/v1/telegram_links?chat_id=eq.${chatId}`, {
      method: 'PATCH',
      headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: null, linked_at: null }),
    });
    await reply('Bildirişlər dayandırıldı. Yenidən bağlamaq üçün AutoTender-də "Hesab" bölməsinə baxın.');
  } else {
    await reply('Salam! Bildirişləri almaq üçün AutoTender → Hesab → "Telegram-ı bağla" düyməsinə basın.');
  }
  return new Response('ok');
});
