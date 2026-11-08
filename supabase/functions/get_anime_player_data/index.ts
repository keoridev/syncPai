// ==============================================================================
// SyncPai: Supabase Edge Function - get_anime_player_data
// BFF (Backend-For-Frontend) Агрегатор видеопотоков и озвучек (AniLibria + Kodik)
// Стек: TypeScript / Deno / Supabase Edge Functions
// ==============================================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

// Заголовки CORS для вызова из Flutter / Web
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

interface RequestPayload {
  shikimori_id?: number | string;
  title?: string;
}

interface EpisodeDirectStream {
  episode: number;
  link: string;
}

interface TranslationItem {
  studio_name: string;
  translation_type: string; // 'dub' | 'sub' | 'raw'
  is_direct_stream: boolean;
  episodes?: EpisodeDirectStream[];
  iframe_url?: string;
}

interface PlayerDataResponse {
  shikimori_id: number;
  translations: TranslationItem[];
  error?: string;
}

serve(async (req: Request) => {
  // 1. Обработка OPTIONS (CORS preflight)
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    let shikimoriId: number | null = null;
    let animeTitle: string | null = null;

    // 2. Чтение входных данных из JSON body или URL query
    if (req.method === "POST") {
      try {
        const body: RequestPayload = await req.json();
        if (body.shikimori_id) {
          shikimoriId = Number(body.shikimori_id);
        }
        if (body.title) {
          animeTitle = String(body.title).trim();
        }
      } catch (_) {
        // Если тело не JSON, пробуем query params
      }
    }

    if (!shikimoriId) {
      const url = new URL(req.url);
      const qId = url.searchParams.get("shikimori_id");
      if (qId) shikimoriId = Number(qId);
      const qTitle = url.searchParams.get("title");
      if (qTitle) animeTitle = qTitle.trim();
    }

    // Валидация входных данных
    if (!shikimoriId || isNaN(shikimoriId)) {
      return new Response(
        JSON.stringify({
          error: "Поле shikimori_id обязательно и должно быть числом.",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // 3. Если название не передано — получаем через Shikimori API
    if (!animeTitle && shikimoriId) {
      try {
        const shikiRes = await fetch(`https://shikimori.io/api/animes/${shikimoriId}`, {
          headers: { "User-Agent": "SyncPai-BFF/1.0", Accept: "application/json" },
        });
        if (shikiRes.ok) {
          const shikiJson = await shikiRes.json();
          animeTitle = shikiJson.russian || shikiJson.name || null;
        }
      } catch (_) {}
    }

    // 4. Чтение безопасных секретов из окружения Supabase Secrets
    const KODIK_TOKEN = Deno.env.get("KODIK_TOKEN") || "9a3a536480e4f80a934440a34b223c25"; // fallback dev/public token
    const ANILIBRIA_BASE = "https://anilibria.top";

    // 5. Параллельные запросы к балансерам (Promise.allSettled)
    const [kodikResult, anilibriaResult] = await Promise.allSettled([
      fetchKodikData(shikimoriId, KODIK_TOKEN),
      fetchAniLibriaData(shikimoriId, animeTitle, ANILIBRIA_BASE),
    ]);

    const translations: TranslationItem[] = [];

    // 5. Обработка ответа AniLibria (прямые .m3u8 HLS потоки)
    if (anilibriaResult.status === "fulfilled" && anilibriaResult.value) {
      const anilibriaItem = anilibriaResult.value;
      if (anilibriaItem.episodes && anilibriaItem.episodes.length > 0) {
        translations.push(anilibriaItem);
      }
    }

    // 6. Обработка ответа Kodik (iframe плееры для десятков студий: StudioBand, Dream Cast, AniDUB и др.)
    if (kodikResult.status === "fulfilled" && Array.isArray(kodikResult.value)) {
      translations.push(...kodikResult.value);
    }

    // 7. Сборка ответа по контракту ТЗ
    const responseData: PlayerDataResponse = {
      shikimori_id: shikimoriId,
      translations: translations,
    };

    return new Response(JSON.stringify(responseData), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({
        error: `Ошибка агрегации видеоплеера: ${message}`,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

/**
 * Запрос к Kodik API для поиска озвучек по shikimori_id
 */
async function fetchKodikData(
  shikimoriId: number,
  token: string
): Promise<TranslationItem[]> {
  try {
    const url = `https://kodikapi.com/search?token=${token}&shikimori_id=${shikimoriId}&with_episodes=true&limit=50`;
    const res = await fetch(url, {
      headers: {
        "User-Agent": "SyncPai-BFF/1.0",
        Accept: "application/json",
      },
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
      if (iframe.startsWith("//")) {
        iframe = `https:${iframe}`;
      }

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

/**
 * Запрос к AniLibria API для получения прямых HLS видеопотоков (.m3u8)
 */
async function fetchAniLibriaData(
  shikimoriId: number,
  title: string | null,
  baseUrl: string
): Promise<TranslationItem | null> {
  try {
    // 1. Попытка поиска по shikimori_id через каталог
    let releaseData: any = null;

    if (title && title.length > 1) {
      const searchUrl = `${baseUrl}/api/v1/app/search/releases?query=${encodeURIComponent(
        title
      )}`;
      const res = await fetch(searchUrl, {
        headers: { "User-Agent": "SyncPai-BFF/1.0" },
      });
      if (res.ok) {
        const searchJson = await res.json();
        const list = Array.isArray(searchJson)
          ? searchJson
          : searchJson.data || [];
        if (list.length > 0) {
          releaseData = list[0];
        }
      }
    }

    if (!releaseData) {
      // Фолбек: проверка свежих релизов
      const latestUrl = `${baseUrl}/api/v1/anime/releases/latest?limit=15`;
      const res = await fetch(latestUrl, {
        headers: { "User-Agent": "SyncPai-BFF/1.0" },
      });
      if (res.ok) {
        const json = await res.json();
        const list = Array.isArray(json) ? json : json.data || [];
        releaseData = list.find(
          (item: any) =>
            item.shikimori?.id === shikimoriId ||
            (title && item.russian?.includes(title))
        );
      }
    }

    if (!releaseData) return null;

    // 2. Если у найденного релиза нет детального списка серий (пришел из поиска), запрашиваем детали
    if (!releaseData.episodes || !Array.isArray(releaseData.episodes) || releaseData.episodes.length === 0) {
      const releaseId = releaseData.id || releaseData.code;
      if (releaseId) {
        try {
          const detailUrl = `${baseUrl}/api/v1/anime/releases/${releaseId}`;
          const detailRes = await fetch(detailUrl, {
            headers: { "User-Agent": "SyncPai-BFF/1.0" },
          });
          if (detailRes.ok) {
            const detailJson = await detailRes.json();
            releaseData = detailJson.data || detailJson;
          }
        } catch (_) {}
      }
    }

    // Извлечение прямых HLS потоков
    const episodes: EpisodeDirectStream[] = [];
    const rawEpisodes = releaseData.episodes || [];

    for (const ep of rawEpisodes) {
      const epNum = ep.ordinal ?? ep.sort_order ?? 1;
      const hls = ep.hls_720 || ep.hls_1080 || ep.hls_480;

      if (hls && typeof hls === "string") {
        let streamUrl = hls;
        if (streamUrl.startsWith("//")) {
          streamUrl = `https:${streamUrl}`;
        } else if (!streamUrl.startsWith("http")) {
          streamUrl = `${baseUrl}${streamUrl.startsWith("/") ? "" : "/"}${streamUrl}`;
        }

        episodes.push({
          episode: epNum,
          link: streamUrl,
        });
      }
    }

    if (episodes.length === 0) return null;

    episodes.sort((a, b) => a.episode - b.episode);

    return {
      studio_name: "AniLibria",
      translation_type: "dub",
      is_direct_stream: true,
      episodes: episodes,
    };
  } catch (_) {
    return null;
  }
}

