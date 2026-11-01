# AutoTender — quraşdırma və sınaq (sıra ilə)

## A. Supabase

1. **Ehtiyat nüsxə**: Settings → Database → Backups (və ya əvvəlcədən `stores`, `requests`, `bids` cədvəllərini CSV kimi yükləyin).
2. **Yeni (boş) layihədə ən sadə yol**: SQL Editor → New query → `supabase/AutoTender_BAZA_hamisi.sql` faylının bütün məzmununu yapışdırıb **bir dəfə** Run edin. Bu fayl aşağıdakı bütün migrasiyaları (köhnə 6 + yeni 5) düzgün sıra ilə birləşdirir və təmiz bazada təkrar işlətməyə də davamlıdır.
   Ayrı-ayrı işlətmək istəsəniz: bu faylları **ardıcıllıqla** yapışdırıb Run edin (hər biri təkrar işlədilə bilər):
   1. `supabase/migrations/20261029120000_secure_rewrite.sql`
   2. `supabase/migrations/20261101120000_billing_plans.sql`
   3. `supabase/migrations/20261102120000_safety_privacy.sql` (şikayət, dayandırma, məlumatı yüklə / hesabı sil)
   4. `supabase/migrations/20261103120000_services_ratings.sql` (usta/servis xidməti, təklifə şəkil, reytinqə təsir)
   5. `supabase/migrations/20261104120000_deal_flow_plans.sql` (razılaşma alınmayanda yeni qayda, Plus hədiyyə coin, bonus 2 coin)

   **Artıq 1–4-cü migrasiyanı işlədibsinizsə**, yalnız 5-ci faylı (`20261104120000_deal_flow_plans.sql`) SQL Editor-da Run edin.
3. **Authentication → Sign In / Providers**: "Allow anonymous sign-ins" → **ON**. Email provider-də "Confirm email" → **OFF** (tövsiyə).
4. **Authentication → URL Configuration**: Site URL = Netlify ünvanınız (məs. `https://autotender.netlify.app`), Redirect URLs-ə eyni ünvanı əlavə edin (parol bərpası üçün).
5. **Admin hesabı**: tətbiqdə "Satıcı girişi → Yeni mağaza aç" ilə öz e-poçtunuzla qeydiyyatdan keçin, sonra SQL Editor-da:
   `insert into public.admins (user_id, email) select id, email from auth.users where email = 'SIZIN_EMAIL' on conflict do nothing;`
   Menyuda "Admin paneli" görünəcək.
6. **Köhnə mağazalar** (hesabsız): admin paneldə "HESAB BAĞLI DEYİL" yazılanlar üçün satıcı qeydiyyatdan keçəndən sonra:
   `select admin_assign_store_owner('<store_id>', '<satici_email>');`

## B. Netlify-a keçid (Bolt-dan çıxış)

Netlify mənbə koddan build edir, ona görə ZIP-i **GitHub-a** qoymaq ən rahat yoldur:
1. github.com-da boş repo yaradın (Private). ZIP-i açın, içindəki faylları (`project` qovluğunun içini) repo-ya yükləyin ("Add file → Upload files"; `.env` yüklənməməlidir — `.gitignore` onu artıq çıxarır).
2. Netlify → Add new site → Import from Git → repo-nu seçin. Build ayarları `netlify.toml`-dan avtomatik oxunur (`npm run build`, `dist`).
3. **Site configuration → Environment variables** əlavə edin (`.env` faylınızdakı eyni dəyərlər):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
4. Deploy. Sonra Domain management-dən öz domeninizi bağlayın və A bölməsinin 4-cü addımındakı Site URL-i yeniləyin.
5. Hər dəyişiklikdən sonra yeni ZIP-i repo-ya yükləyin — Netlify özü yenidən yerləşdirir.

## C. Telegram bildirişləri (pulsuz)

1. Telegram-da **@BotFather** → `/newbot` → bot adı seçin → **token** alın (məs. `123456:ABC...`).
2. Supabase → **Edge Functions → Secrets** əlavə edin:
   - `TELEGRAM_BOT_TOKEN` = BotFather tokeni
   - `TELEGRAM_WEBHOOK_SECRET` = istənilən uzun təsadüfi mətn
   - `WEBHOOK_SECRET` = başqa uzun təsadüfi mətn
   - `SITE_URL` = saytınızın ünvanı
3. **Edge Functions → Deploy a new function** (Via Editor) ilə iki funksiya yaradın, kodları `supabase/functions/telegram-webhook/index.ts` və `supabase/functions/telegram-notify/index.ts` fayllarından yapışdırın. Hər ikisində **"Verify JWT" söndürülməlidir** (CLI istifadə edirsinizsə `supabase/config.toml` bunu edir).
4. Telegram-a webhook-u bildirin — brauzerin ünvan sətrinə yazın (ölçüləri öz dəyərlərinizlə əvəz edin):
   `https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://csyesialbkoxbelejqmh.supabase.co/functions/v1/telegram-webhook&secret_token=<TELEGRAM_WEBHOOK_SECRET>`
   Cavabda `"ok":true` olmalıdır.
5. Supabase → **Database → Webhooks → Create**: Table `in_app_notifications`, Events: **Insert**, Type: Supabase Edge Functions → `telegram-notify`, HTTP Headers-ə əlavə edin `x-webhook-secret` = `WEBHOOK_SECRET` dəyəri.
6. Tətbiqdə admin panel → "Qiymətlər və mətnlər" → **Telegram bot adı** (@ olmadan) yazıb Saxla. İndi satıcılar "Hesab → Telegram-ı bağla" ilə qoşula bilər. Admin də eyni paneldən qoşulub yeni ödəniş sifarişlərini Telegram-da görür.

## D. Ödəniş və qiymətlər

Başlanğıc kataloq: 20 coin = 10 AZN, 50 coin = 20 AZN, 150 coin = 50 AZN, **Plus 19 AZN/ay** (hər alışda 30 hədiyyə coin + təklif haqqı 50% ucuz: 0.5 coin + bazar analizi), **Pro 39 AZN/ay** (təkliflər pulsuz + dərin analiz).
Plan qiymətləri **təklifdir** — admin paneldə "Qiymətlər və mətnlər"dən dəyişin.
Ödəniş axını (əllə təsdiq): satıcı Hesab → paketi seçir → sifariş kodu (AT-XXXXXX) alır → kartınıza/hesabınıza köçürür, izahda kodu yazır → admin paneldə **"Ödənişi təsdiqlə"** → coin/plan avtomatik verilir.
Admin paneldə mutləq doldurun: **Ödəniş kartı** (kart nömrəsi və kart sahibinin adı — satıcı bunu "Ödəniş" pəncərəsində görür və kart nömrəsini bir toxunuşla köçürür) və **Dəstək WhatsApp nömrəsi**. Kart nömrəsi yazılmayıbsa admin panelində sarı xəbərdarlıq çıxır, satıcıya isə "Kartı WhatsApp-da istə" düyməsi göstərilir.
Satıcı üçün axın: Hesab → paketi seç → **Ödəniş** pəncərəsi açılır: 1) məbləği karta köçür, 2) köçürmənin "Təyinat/Qeyd" xanasına sifariş kodunu yaz, 3) qəbzi WhatsApp-da göndər. Pəncərəni sonra "Sifarişlər → Necə ödəyim?" ilə yenidən açmaq olar.
Pilot mağazalara əllə plan vermək: mağaza kartındakı Free/Plus/Pro düymələri (30 gün).

## D2. Usta / servis xidməti və reytinq

- Sorğu iki növdür: **Detal** və **Usta / servis**. Xidmət sorğusunda: xidmət növü (10 kateqoriya), şəhər, rayon, "yanıma gəlsin", "servis / fərdi usta / fərqi yoxdur".
- Təchizatçı növü: **Mağaza / Servis / Usta**. Profildə: nə təklif edir (hissə və/ya xidmət), xidmət növləri, şəhərlər, yerinə gedirmi. Sorğu yalnız uyğun təchizatçının lentinə və bildirişinə düşür (server qaydası `request_matches_store`).
- Mövcud mağazalar avtomatik "Mağaza + ehtiyat hissəsi" olaraq qalır; usta və servislər profilindən xidmət seçməlidir.
- Xidmət təklifi: qiymət (dəqiq / …dən başlayır), iş müddəti, zəmanət, qeyd, ən çox 3 şəkil. Hissə təklifinə də 3 şəkil əlavə olunur. Şəkillər `part-images` bucket-ində təchizatçının öz qovluğundadır.
- **Reytinq**: "Razılaşma alınmadı" hər dəfə mağazanın reytinqini aşağı salır (yarım çəkili 1 ulduz, yeni mağaza bir şikayətlə dibə düşməsin deyə 2 neytral başlanğıc rəy var). Məs.: rəysiz mağaza 1 uğursuz razılaşmadan sonra 4.2, ikincidən sonra 3.7. Admin səhv hallarda sayı `select admin_set_failed_deals('<store_id>', 0);` ilə düzəldə bilər.
- Bazar analizi yalnız detal sorğularını sayır.

## D3. Razılaşma alınmayanda (yeni qayda)

- Alıcı "Razılaşma alınmadı" basanda sorğu **yenidən hamıya açılmır** — əvvəl təklif vermiş digər mağazalara qayıdır (24 saat, yalnız onlar arasından seçir, yeni mağaza təklif verə bilmir).
- Əvvəlki mağazalardan heç kim qalmayıbsa, sorğu yenidən hamıya açılır (6 saat) və uyğun mağazalara bildiriş gedir.
- Pozan mağaza: satış bonusu geri alınır, reytinqi düşür, "uğursuz razılaşma" sayı artır. Eyni mağaza eyni sorğuya ikinci dəfə təklif verə bilmir (saxta təklifi təkrarlamaq olmur).
- Son 30 gündə 3 və daha çox uğursuz razılaşması olan mağaza haqqında admin bildiriş alır.

## D4. Plan iqtisadiyyatı (təklif)

- Bonus: tender qalibi **2 coin** (qaydaya əsasən gündəlik tavan 3 coin).
- Coin qiyməti: 0.50 / 0.40 / 0.33 AZN. Free: təklif 1 coin.
- **Plus 19 AZN**: 30 hədiyyə coin (≈ 15 AZN dəyər) + hər təklif 0.5 coin. Hədiyyə coin ≈ 12 AZN dəyərindədir, yəni plan haqqının real xərci ≈ 7 AZN; hər təklifdə 0.2 AZN qənaət olur. Hesab: ayda ~35+ təklif verən mağaza üçün Plus Free-dən ucuzdur (üstəgəl analiz).
- **Pro 39 AZN**: təkliflər limitsiz, dərin analiz. Hesab: ayda ~100+ təklif verən və ya dərin analiz istəyən mağaza üçün.
- Qiymətləri istənilən vaxt SQL ilə dəyişin: `update billing_catalog set price_azn = 19, coins = 30 where key = 'plan_plus_30';`

## Dizayn
Logo: ₼ işarəli qiymət etiketi. Şəkillərə toxunanda tətbiqin içində böyük pəncərədə açılır. Menyuda yalnız "Tarixçəni sil" / "Mağaza hesabını sil" var (JSON yükləmə çıxarılıb). Açıq, "şüşə" (glass) üslubu: üzən şəffaf başlıq və alt menyu, yumşaq yaşıl-sarı fon, ağ kartlar, iri qalın qiymət şrifti (Archivo), yuvarlaq düymələr. Heç yerdə yana sürüşdürmə yoxdur (seçimlər sətirlərə düzülür). Sorğu və təklif kartının üstündə qalan vaxt zolağı var. Coin balansı yalnız yuxarıdakı sarı düymədə göstərilir (toxunanda Hesab açılır). Şriftlər Google Fonts-dan yüklənir. Qeyd: dizayn real cihazda baxılmayıb, ilk açılışda telefonda yoxlayın.

## E. Sınaq siyahısı (real telefonda)

1. Alıcı (qeydiyyatsız): sorğu göndər (şəkil ilə), təklif gələndə seç, WhatsApp düyməsi açılır?
2. Satıcı (ikinci telefon/brauzer): qeydiyyat, lentdə sorğu görünür? Telegram-a bildiriş gəldi? Təklif ver (−1 coin).
3. Alıcı təklifi seçir → satıcıda "Seçildi" və +2 coin. "Razılaşma alınmadı" → sorğu əvvəlki mağazalara qayıdır; başqası qalmayıbsa hamıya açılır.
4. Vaxtı bitən sorğuda coin geri qayıdır.
5. Hesab → coin sifarişi → admin təsdiqi → balans artır. Plus verəndən sonra təklif 0.5 coin, Pro-da pulsuz.
6. Android Chrome-da "Quraşdır" banneri, iPhone Safari-də "Ana ekrana əlavə et" izahatı.
7. İnternet kəsiləndə/zəifləyəndə səhifə donmur?
8. Usta: qeydiyyatda "Usta" + xidmət + şəhər seçin; alıcıdan xidmət sorğusu göndərin; usta lentdə görür? Təklif + şəkil. Başqa şəhərdəki usta görmür?
9. "Razılaşma alınmadı" basın: mağazanın reytinqi düşdü?
10. Admin: menyuda "Alıcı rejiminə keç" / "Satıcı panelinə keç" / "Admin panelinə keç" düymələri işləyir? (Admin düyməsi yalnız adminə görünür, adi alıcı yalnız "Satıcı kimi qoşul" görür.) Ödəniş kartını yazın, satıcı hesabından sifariş verib "Ödəniş" pəncərəsini yoxlayın.

## Nə dəyişdi (qısa)
- Coin, təklif qəbulu, bonus, geri qaytarma, vaxt bitməsi, ödəniş təsdiqi, plan — hamısı serverdə (RPC). Brauzerdən coin/plan dəyişmək mümkün deyil.
- Satıcı telefonu yalnız alıcı təklifi seçəndən sonra açılır; təkliflər bir-birinə görünmür; qeydlərdə telefon/WhatsApp yazmaq bloklanır.
- Plus/Pro: server plan yoxlayır (analiz məlumatı Free hesaba heç göndərilmir).
- Analizdə orta qiymət ən azı 3 satış olanda göstərilir (tək mağazanın qiyməti sızmasın).
