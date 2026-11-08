// ==============================================================================
// SyncPai: Supabase Edge Function - get_catalog
// BFF (Backend-For-Frontend) Прокси для каталога и поиска Shikimori API v1
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

    // 2. Чтение входных параметров из JSON body (POST) или searchParams (GET)
    if (req.method === "POST") {
      try {
        const body: RequestPayload = await req.json();
        if (body.page) page = Math.max(1, Number(body.page) || 1);
        if (body.limit) limit = Math.min(50, Math.max(1, Number(body.limit) || 30));
        if (body.search && typeof body.search === "string") {
          search = body.search.trim();
        }
      } catch (_) {
        // Fallback на query параметры при невалидном body
      }
    }

    if (req.method === "GET" || (page === 1 && limit === 30 && !search)) {
      const url = new URL(req.url);
      const qPage = url.searchParams.get("page");
      if (qPage) page = Math.max(1, Number(qPage) || 1);
      const qLimit = url.searchParams.get("limit");
      if (qLimit) limit = Math.min(50, Math.max(1, Number(qLimit) || 30));
      const qSearch = url.searchParams.get("search");
      if (qSearch) search = qSearch.trim();
    }

    const queryParams = new URLSearchParams({
      page: String(page),
      limit: String(limit),
      order: "popularity",
    });

    if (search.length > 0) {
      queryParams.set("search", search);
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
      headers: { ...corsHeaders, "Content-Type": "application/json" },
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

