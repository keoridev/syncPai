// ==============================================================================
// SyncPai: Supabase Edge Function - get_catalog (Production BFF)
// Агрегатор и прокси каталога Shikimori API v1 с поддержкой фильтров, жанров и CDN
// Стек: TypeScript / Deno / Supabase Edge Functions
// ==============================================================================

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

interface RequestPayload {
  page?: number | string;
  limit?: number | string;
  search?: string;
  order?: string;
  status?: string;
  genre?: string | number;
}

const PRIMARY_URL = "https://shikimori.me/api/animes";
const FALLBACK_URL_ONE = "https://shikimori.one/api/animes";
const FALLBACK_URL_IO = "https://shikimori.io/api/animes";

serve(async (req: Request) => {
  // 1. CORS Preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    let page = 1;
    let limit = 30;
    let search = "";
    let order = "popularity";
    let status: string | null = null;
    let genre: string | null = null;

    // 2. Чтение входных параметров из JSON body (POST) или searchParams (GET)
    if (req.method === "POST") {
      try {
        const body: RequestPayload = await req.json();
        if (body.page) page = Math.max(1, Number(body.page) || 1);
        if (body.limit) limit = Math.min(50, Math.max(1, Number(body.limit) || 30));
        if (body.search && typeof body.search === "string") {
          search = body.search.trim();
        }
        if (body.order && typeof body.order === "string") {
          order = body.order.trim();
        }
        if (body.status && typeof body.status === "string") {
          status = body.status.trim();
        }
        if (body.genre !== undefined && body.genre !== null) {
          genre = String(body.genre).trim();
        }
      } catch (_) {
        // Fallback на query параметры при невалидном body
      }
    }

    if (req.method === "GET") {
      const url = new URL(req.url);
      const qPage = url.searchParams.get("page");
      if (qPage) page = Math.max(1, Number(qPage) || 1);
      const qLimit = url.searchParams.get("limit");
      if (qLimit) limit = Math.min(50, Math.max(1, Number(qLimit) || 30));
      const qSearch = url.searchParams.get("search");
      if (qSearch) search = qSearch.trim();
      const qOrder = url.searchParams.get("order");
      if (qOrder) order = qOrder.trim();
      const qStatus = url.searchParams.get("status");
      if (qStatus) status = qStatus.trim();
      const qGenre = url.searchParams.get("genre");
      if (qGenre) genre = qGenre.trim();
    }

    const queryParams = new URLSearchParams({
      page: String(page),
      limit: String(limit),
    });

    if (search.length > 0) {
      queryParams.set("search", search);
    } else {
      queryParams.set("order", order || "popularity");
      if (status && status.length > 0) {
        queryParams.set("status", status);
      }
      if (genre && genre.length > 0) {
        queryParams.set("genre", genre);
      }
    }

    const headers = {
      "User-Agent": "SyncPai-BFF/1.0",
      "Accept": "application/json",
    };

    // 3. Вызов Shikimori API с каскадным fallback для максимальной отказоустойчивости
    let data: unknown = null;
    const targets = [
      `${PRIMARY_URL}?${queryParams.toString()}`,
      `${FALLBACK_URL_ONE}?${queryParams.toString()}`,
      `${FALLBACK_URL_IO}?${queryParams.toString()}`,
    ];

    for (const targetUrl of targets) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 6000);

        const res = await fetch(targetUrl, {
          method: "GET",
          headers,
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        if (res.ok) {
          data = await res.json();
          break;
        }
      } catch (_) {
        // Пробуем следующее зеркало при таймауте или сетевой ошибке
        continue;
      }
    }

    if (!data) {
      return new Response(
        JSON.stringify({ error: "Не удалось получить каталог от Shikimori API" }),
        {
          status: 502,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    return new Response(JSON.stringify(data), {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=180", // Кэш на 3 минуты для CDN Edge
      },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: (error as Error).message || "Внутренняя ошибка Edge Function" }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
