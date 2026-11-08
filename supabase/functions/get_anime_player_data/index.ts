// ==============================================================================
// SyncPai: Supabase Edge Function - get_anime_player_data (Production BFF)
// Гибридный агрегатор видеопотоков (AniLibria + Kodik) с таймингами скипов,
// качеством FHD/HD/SD и превью перемотки.
// Стек: TypeScript / Deno / Supabase Edge Functions
// ==============================================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

interface RequestPayload {
  shikimori_id?: number | string;
  title_ru?: string;
  title_en?: string;
  title?: string;
}

interface EpisodeSkips {
  opening?: [number, number] | null;
  ending?: [number, number] | null;
}

interface EpisodeData {
  episode: number;
  name?: string | null;
  duration?: number | null;
  link: string;
  fhd?: string | null;
  hd?: string | null;
  sd?: string | null;
  preview?: string | null;
  skips?: EpisodeSkips | null;
}

interface TranslationItem {
  studio_name: string;
  translation_type: string; // 'dub' | 'sub' | 'raw'
  is_direct_stream: boolean;
  episodes?: EpisodeData[];
  iframe_url?: string | null;
}

const ANILIBRIA_BASE = "https://anilibria.top";
const KODIK_TOKEN = Deno.env.get("KODIK_TOKEN") || "9a3a536480e4f80a934440a34b223c25";

serve(async (req: Request) => {
  // 1. CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    let shikimoriId: number | null = null;
    let titleRu: string | null = null;
    let titleEn: string | null = null;

    if (req.method === "POST") {
      try {
        const body: RequestPayload = await req.json();
        if (body.shikimori_id) shikimoriId = Number(body.shikimori_id);
        if (body.title_ru) titleRu = String(body.title_ru).trim();
        if (body.title_en) titleEn = String(body.title_en).trim();
        if (!titleRu && body.title) titleRu = String(body.title).trim();
      } catch (_) {}
    }

    if (!shikimoriId) {
      const url = new URL(req.url);
      const qId = url.searchParams.get("shikimori_id");
      if (qId) shikimoriId = Number(qId);
      const qRu = url.searchParams.get("title_ru") || url.searchParams.get("title");
      if (qRu) titleRu = qRu.trim();
      const qEn = url.searchParams.get("title_en");
      if (qEn) titleEn = qEn.trim();
    }

    if (!shikimoriId || isNaN(shikimoriId)) {
      return new Response(
        JSON.stringify({ error: "Поле shikimori_id обязательно и должно быть числом." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Если названия не переданы, получаем их из Shikimori API
    if (!titleRu && !titleEn && shikimoriId) {
      try {
        const shikiRes = await fetch(`https://shikimori.io/api/animes/${shikimoriId}`, {
          headers: { "User-Agent": "SyncPai-BFF/1.0", Accept: "application/json" },
          signal: AbortSignal.timeout(4500),
        });
        if (shikiRes.ok) {
          const shikiJson = await shikiRes.json();
          titleRu = shikiJson.russian || null;
          titleEn = shikiJson.name || null;
        }
      } catch (_) {}
    }

    // =========================================================================
    // ШАГ 1: Поиск в базе AniLibria API (Приоритетный источник: direct HLS)
    // =========================================================================
    const anilibriaRelease = await findAniLibriaRelease(shikimoriId, titleRu, titleEn);

    if (anilibriaRelease && Array.isArray(anilibriaRelease.episodes) && anilibriaRelease.episodes.length > 0) {
      const episodes: EpisodeData[] = [];

      for (const ep of anilibriaRelease.episodes) {
        const epNum = ep.ordinal ?? ep.sort_order ?? 1;
        const fhd = normalizeUrl(ep.hls_1080);
        const hd = normalizeUrl(ep.hls_720);
        const sd = normalizeUrl(ep.hls_480);
        const link = fhd || hd || sd;

        if (!link) continue;

        let previewUrl: string | null = null;
        const rawPreview = ep.preview?.optimized?.src || ep.preview?.src || ep.preview?.preview;
        if (rawPreview && typeof rawPreview === "string") {
          previewUrl = rawPreview.startsWith("http")
            ? rawPreview
            : `${ANILIBRIA_BASE}${rawPreview.startsWith("/") ? "" : "/"}${rawPreview}`;
        }

        let skips: EpisodeSkips | null = null;
        const hasOpening = ep.opening && ep.opening.start != null && ep.opening.stop != null;
        const hasEnding = ep.ending && ep.ending.start != null && ep.ending.stop != null;
        if (hasOpening || hasEnding) {
          skips = {
            opening: hasOpening ? [ep.opening.start, ep.opening.stop] : null,
            ending: hasEnding ? [ep.ending.start, ep.ending.stop] : null,
          };
        }

        episodes.push({
          episode: epNum,
          name: ep.name ? String(ep.name) : `Серия ${epNum}`,
          duration: ep.duration ?? null,
          link,
          fhd,
          hd,
          sd,
          preview: previewUrl,
          skips,
        });
      }

      episodes.sort((a, b) => a.episode - b.episode);

      if (episodes.length > 0) {
        const releaseTitle = anilibriaRelease.name?.main || anilibriaRelease.name?.english || titleRu || titleEn;
        return new Response(
          JSON.stringify({
            source: "anilibria",
            shikimori_id: shikimoriId,
            title: releaseTitle,
            episodes: episodes,
            translations: [
              {
                studio_name: "AniLibria",
                translation_type: "dub",
                is_direct_stream: true,
                episodes: episodes,
              },
            ],
          }),
          {
            status: 200,
            headers: {
              ...corsHeaders,
              "Content-Type": "application/json",
              "Cache-Control": "public, max-age=300",
            },
          }
        );
      }
    }

    // =========================================================================
    // ШАГ 2: Резервный источник — Kodik API (если AniLibria вернула 0 серий)
    // =========================================================================
    const kodikTranslations = await fetchKodikData(shikimoriId, KODIK_TOKEN);

    return new Response(
      JSON.stringify({
        source: "kodik",
        shikimori_id: shikimoriId,
        title: titleRu || titleEn || "",
        episodes: [],
        translations: kodikTranslations,
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=300",
        },
      }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ error: `Ошибка агрегации плеера: ${message}` }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

function normalizeUrl(url: string | null | undefined): string | null {
  if (!url || typeof url !== "string") return null;
  const trimmed = url.trim();
  if (trimmed.startsWith("//")) return `https:${trimmed}`;
  if (!trimmed.startsWith("http")) {
    return `${ANILIBRIA_BASE}${trimmed.startsWith("/") ? "" : "/"}${trimmed}`;
  }
  return trimmed;
}

/**
 * Поиск релиза в AniLibria по title_ru / title_en с проверкой shikimori.id
 */
async function findAniLibriaRelease(
  shikimoriId: number,
  titleRu: string | null,
  titleEn: string | null
): Promise<any | null> {
  const queries = [titleRu, titleEn].filter((q): q is string => Boolean(q && q.length > 1));

  for (const query of queries) {
    try {
      const searchUrl = `${ANILIBRIA_BASE}/api/v1/app/search/releases?query=${encodeURIComponent(query)}`;
      const res = await fetch(searchUrl, {
        headers: { "User-Agent": "SyncPai-BFF/1.0", Accept: "application/json" },
        signal: AbortSignal.timeout(4500),
      });

      if (!res.ok) continue;

      const json = await res.json();
      const list: any[] = Array.isArray(json) ? json : (json.data || []);
      if (list.length === 0) continue;

      // 1. Приоритетное точное совпадение по shikimori.id
      let matched = list.find((item) => item.shikimori?.id === shikimoriId);

      // 2. Если нет точного совпадения по shikimori.id, берем первый релевантный результат поиска
      if (!matched) {
        matched = list[0];
      }

      if (matched && matched.id) {
        // Запрашиваем полный объект релиза со всеми сериями
        const detailUrl = `${ANILIBRIA_BASE}/api/v1/anime/releases/${matched.id}`;
        const detailRes = await fetch(detailUrl, {
          headers: { "User-Agent": "SyncPai-BFF/1.0", Accept: "application/json" },
          signal: AbortSignal.timeout(4500),
        });

        if (detailRes.ok) {
          const detailJson = await detailRes.json();
          const release = detailJson.data || detailJson;
          if (release.episodes && release.episodes.length > 0) {
            return release;
          }
        }
      }
    } catch (_) {
      // Игнорируем сетевые сбои отдельных запросов и идем дальше
      continue;
    }
  }

  return null;
}

/**
 * Запрос к Kodik API по shikimori_id
 */
async function fetchKodikData(shikimoriId: number, token: string): Promise<TranslationItem[]> {
  try {
    const url = `https://kodikapi.com/search?token=${token}&shikimori_id=${shikimoriId}&with_episodes=true&limit=50`;
    const res = await fetch(url, {
      headers: { "User-Agent": "SyncPai-BFF/1.0", Accept: "application/json" },
      signal: AbortSignal.timeout(4500),
    });

    if (!res.ok) return [];

    const data = await res.json();
    const results = data.results || [];
    const items: TranslationItem[] = [];
    const seenStudios = new Set<string>();

    for (const r of results) {
      const studio = r.translation?.title || "Неизвестная студия";
      if (seenStudios.has(studio)) continue;
      seenStudios.add(studio);

      let iframe = r.link || "";
      if (iframe.startsWith("//")) iframe = `https:${iframe}`;

      const type = r.translation?.type === "subtitles" ? "sub" : "dub";

      items.push({
        studio_name: studio,
        translation_type: type,
        is_direct_stream: false,
        iframe_url: iframe,
      });
    }

    return items;
  } catch (_) {
    return [];
  }
}
