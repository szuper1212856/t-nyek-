import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2.119.2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PUSH_HOSTS = [
  /(^|\.)googleapis\.com$/,
  /(^|\.)push\.apple\.com$/,
  /(^|\.)mozilla\.com$/,
  /(^|\.)mozaws\.net$/,
  /(^|\.)notify\.windows\.com$/,
];

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const allowedEndpoint = (endpoint: string) => {
  try {
    const url = new URL(endpoint);
    return url.protocol === "https:" && PUSH_HOSTS.some((re) => re.test(url.hostname));
  } catch {
    return false;
  }
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT") ?? "mailto:balazs.kiss@creascola.hu";
  if (!publicKey || !privateKey) return json({ error: "A VAPID kulcsok nincsenek beállítva." }, 500);

  let episodeId = "";
  try {
    episodeId = String((await req.json()).episodeId ?? "");
  } catch {
    return json({ error: "Hibás kérés." }, 400);
  }
  if (!episodeId) return json({ error: "Hiányzik az adás azonosítója." }, 400);

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });

  const { data: isStaff, error: staffError } = await supabase.rpc("is_staff");
  if (staffError || !isStaff) return json({ error: "Ehhez nincs jogosultságod." }, 403);

  const { data: episode, error: episodeError } = await supabase
    .from("episodes")
    .select("id, title, summary, published")
    .eq("id", episodeId)
    .maybeSingle();
  if (episodeError) return json({ error: episodeError.message }, 500);
  if (!episode) return json({ error: "Nincs ilyen adás." }, 404);
  if (!episode.published) return json({ error: "Rejtett adásról nem megy ki értesítés." }, 400);

  const { data: targets, error: targetError } = await supabase.rpc("push_targets");
  if (targetError) return json({ error: targetError.message }, 500);

  webpush.setVapidDetails(subject, publicKey, privateKey);

  const payload = JSON.stringify({
    title: `Új adás: ${episode.title}`,
    body: episode.summary || "Nézd meg a Tények++ legújabb adását.",
    url: `./#/adas/${encodeURIComponent(episode.id)}`,
    tag: `adas-${episode.id}`,
  });

  const list = (targets ?? []).filter((t: { endpoint: string }) => allowedEndpoint(t.endpoint));
  const gone: string[] = [];
  let sent = 0;
  let failed = 0;

  for (let i = 0; i < list.length; i += 50) {
    const batch = list.slice(i, i + 50);
    const results = await Promise.allSettled(
      batch.map((t: { endpoint: string; p256dh: string; auth: string }) =>
        webpush.sendNotification(
          { endpoint: t.endpoint, keys: { p256dh: t.p256dh, auth: t.auth } },
          payload,
          { TTL: 60 * 60 * 24, urgency: "normal", topic: `adas${episode.id.replace(/[^A-Za-z0-9]/g, "").slice(0, 28)}` },
        )
      ),
    );
    results.forEach((r, j) => {
      if (r.status === "fulfilled") sent++;
      else {
        failed++;
        const code = (r.reason as { statusCode?: number })?.statusCode;
        if (code === 404 || code === 410) gone.push(batch[j].endpoint);
      }
    });
  }

  if (gone.length) await supabase.rpc("push_remove", { p_endpoints: gone });
  await supabase.from("episodes").update({ notified_at: new Date().toISOString() }).eq("id", episode.id);

  return json({ sent, failed, removed: gone.length });
});
