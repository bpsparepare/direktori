import "jsr:@supabase/functions-js/edge-runtime.d.ts";

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const jsonHeaders = {
  "Content-Type": "application/json",
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "method_not_allowed" }),
      { status: 405, headers: jsonHeaders },
    );
  }

  const clientId = Deno.env.get("GOOGLE_CLIENT_ID")?.trim() ?? "";
  const clientSecret = Deno.env.get("GOOGLE_CLIENT_SECRET")?.trim() ?? "";
  if (clientId.length === 0 || clientSecret.length === 0) {
    return new Response(
      JSON.stringify({
        error: "missing_google_oauth_config",
        message: "GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET belum diatur",
      }),
      { status: 500, headers: jsonHeaders },
    );
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch (_) {
    return new Response(
      JSON.stringify({ error: "invalid_json_body" }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const refreshToken = String(payload["refresh_token"] ?? "").trim();
  if (refreshToken.length === 0) {
    return new Response(
      JSON.stringify({ error: "missing_refresh_token" }),
      { status: 400, headers: jsonHeaders },
    );
  }

  const googleResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      grant_type: "refresh_token",
      refresh_token: refreshToken,
    }),
  });

  const rawText = await googleResponse.text();
  let data: Record<string, unknown> = {};
  try {
    data = rawText.length === 0 ? {} : JSON.parse(rawText);
  } catch (_) {
    data = { raw: rawText };
  }

  if (!googleResponse.ok) {
    return new Response(
      JSON.stringify({
        error: "google_refresh_failed",
        status: googleResponse.status,
        details: data,
      }),
      { status: googleResponse.status, headers: jsonHeaders },
    );
  }

  return new Response(
    JSON.stringify({
      access_token: String(data["access_token"] ?? ""),
      expires_in: Number(data["expires_in"] ?? 3600),
      token_type: String(data["token_type"] ?? "Bearer"),
    }),
    { status: 200, headers: jsonHeaders },
  );
});
