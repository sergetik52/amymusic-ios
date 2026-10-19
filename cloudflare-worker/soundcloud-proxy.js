/**
 * AmyMusic SoundCloud Anti-Blocking Reverse Proxy (Cloudflare Worker)
 * 
 * Полный обход блокировок SoundCloud (API + Обложки + HLS стриминг аудио)
 * 
 * Инструкция по бесплатному развертыванию:
 * 1. Зарегистрируйтесь на https://dash.cloudflare.com (бесплатно, без карты)
 * 2. В левом меню выберите "Workers & Pages" -> нажмите "Create Application" -> "Create Worker"
 * 3. Нажмите "Deploy"
 * 4. Нажмите "Edit code", удалите весь код из редактора, вставьте ВЕСЬ этот файл и нажмите "Deploy"
 * 5. Скопируйте ваш домен (например, https://my-sc-proxy.username.workers.dev)
 * 6. Вставьте его в AmyMusic: Настройки -> "Адрес вашего Cloudflare Worker" и включите тумблер!
 */

export default {
  async fetch(request, env, ctx) {
    // 1. CORS Preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, HEAD, POST, OPTIONS",
          "Access-Control-Allow-Headers": "*",
          "Access-Control-Max-Age": "86400",
        },
      });
    }

    const url = new URL(request.url);

    if (url.pathname === "/proxy" || url.searchParams.has("url") || request.url.includes("url=")) {
      let rawTarget = url.searchParams.get("url");
      if (request.url.includes("url=")) {
        const idx = request.url.indexOf("url=");
        const tail = request.url.slice(idx + 4);
        if (tail.startsWith("http%3A") || tail.startsWith("https%3A")) {
          try {
            rawTarget = decodeURIComponent(tail);
          } catch (_) {
            rawTarget = tail;
          }
        } else if (tail.startsWith("http://") || tail.startsWith("https://")) {
          rawTarget = tail;
        }
      }
      if (rawTarget) {
        try {
          const dest = new URL(rawTarget);
          const fwdHeaders = new Headers();
          const userAgent = request.headers.get("user-agent") || "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X)";
          fwdHeaders.set("User-Agent", userAgent);
          fwdHeaders.set("Origin", "https://soundcloud.com");
          fwdHeaders.set("Referer", "https://soundcloud.com/");

          // Проброс заголовка Range для перемотки треков и стриминга
          if (request.headers.has("range")) {
            fwdHeaders.set("Range", request.headers.get("range"));
          }

          const res = await fetch(dest.toString(), {
            method: request.method,
            headers: fwdHeaders,
            redirect: "follow",
          });

          // Если это HLS плейлист (.m3u8), переписываем ссылки на чанки через наш воркер
          const contentType = res.headers.get("content-type") || "";
          const isM3u8 = dest.pathname.endsWith(".m3u8") || contentType.includes("mpegurl") || contentType.includes("x-mpegURL");
          if (isM3u8 && res.status >= 200 && res.status < 300) {
            let m3u8Text = await res.text();
            const workerOrigin = url.origin;

            // Переписываем URI="..." (например #EXT-X-MAP:URI="https://...")
            m3u8Text = m3u8Text.replace(/URI="(https:\/\/[^"]+)"/g, (match, target) => {
              return `URI="${workerOrigin}/proxy?url=${encodeURIComponent(target)}"`;
            });
            // Переписываем прямые ссылки на сегменты
            m3u8Text = m3u8Text.replace(/^(https:\/\/[^\r\n]+)$/gm, (match, target) => {
              return `${workerOrigin}/proxy?url=${encodeURIComponent(target)}`;
            });

            const m3u8Headers = new Headers(res.headers);
            m3u8Headers.set("Content-Type", "application/vnd.apple.mpegurl");
            m3u8Headers.set("Access-Control-Allow-Origin", "*");
            m3u8Headers.delete("content-length");

            return new Response(m3u8Text, {
              status: res.status,
              headers: m3u8Headers,
            });
          }

          // Для изображений и .m4s / MP3 чанков аудио
          const respHeaders = new Headers(res.headers);
          respHeaders.set("Access-Control-Allow-Origin", "*");
          respHeaders.set("Access-Control-Allow-Methods", "GET, HEAD, POST, OPTIONS");
          respHeaders.set("Access-Control-Allow-Headers", "*");
          // Кэширование картинок на 7 дней
          if (dest.hostname.includes("sndcdn.com")) {
            respHeaders.set("Cache-Control", "public, max-age=604800, immutable");
          }

          return new Response(res.body, {
            status: res.status,
            statusText: res.statusText,
            headers: respHeaders,
          });
        } catch (err) {
          return new Response(JSON.stringify({ error: err.message }), {
            status: 502,
            headers: {
              "Content-Type": "application/json",
              "Access-Control-Allow-Origin": "*",
            },
          });
        }
      }
    }

    // 3. Маршрутизация запросов к API SoundCloud v2
    const targetHost = request.headers.get("x-target-host") || "api-v2.soundcloud.com";
    const targetUrl = new URL(request.url);
    targetUrl.hostname = targetHost;
    targetUrl.protocol = "https:";
    targetUrl.port = "";

    const newHeaders = new Headers(request.headers);
    newHeaders.delete("host");
    newHeaders.delete("cf-connecting-ip");
    newHeaders.delete("cf-ipcountry");
    newHeaders.delete("cf-ray");
    newHeaders.delete("cf-visitor");
    newHeaders.delete("x-real-ip");
    newHeaders.delete("x-forwarded-for");
    newHeaders.delete("x-forwarded-proto");
    newHeaders.set("Origin", "https://soundcloud.com");
    newHeaders.set("Referer", "https://soundcloud.com/");

    if (!newHeaders.has("User-Agent")) {
      newHeaders.set("User-Agent", "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148");
    }

    const newRequest = new Request(targetUrl.toString(), {
      method: request.method,
      headers: newHeaders,
      body: request.method !== "GET" && request.method !== "HEAD" ? request.body : undefined,
      redirect: "follow",
    });

    try {
      const response = await fetch(newRequest);
      const responseHeaders = new Headers(response.headers);
      responseHeaders.set("Access-Control-Allow-Origin", "*");
      responseHeaders.set("Access-Control-Allow-Methods", "GET, HEAD, POST, OPTIONS");
      responseHeaders.set("Access-Control-Allow-Headers", "*");
      responseHeaders.delete("content-security-policy");

      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: responseHeaders,
      });
    } catch (err) {
      return new Response(JSON.stringify({ error: err.message }), {
        status: 502,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      });
    }
  },
};
