import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const jsonHeaders = {
  "Content-Type": "application/json",
};

// Refresh dilakukan bila access token tersisa kurang dari ini.
const EXPIRY_BUFFER_MS = 5 * 60 * 1000;

const TOKEN_COLUMNS =
  "id, access_token, refresh_token, token_expiry, user_id, google_email, " +
  "is_shared_company_account, updated_at";

type TokenRow = {
  id: string;
  access_token: string | null;
  refresh_token: string | null;
  token_expiry: string | null;
  user_id: string | null;
  google_email: string | null;
  is_shared_company_account: boolean | null;
  updated_at: string | null;
};

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

async function refreshWithGoogle(
  clientId: string,
  clientSecret: string,
  refreshToken: string,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
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
  return { ok: googleResponse.ok, status: googleResponse.status, data };
}

type OAuthClient = { id: string; secret: string };

/// Client OAuth yang tersedia, client Web lebih dulu. Client yang sama
/// tidak dicoba dua kali.
function oauthClients(): OAuthClient[] {
  const daftar: OAuthClient[] = [];
  for (const [idKey, secretKey] of [
    ["GOOGLE_AUTH_CLIENT_ID", "GOOGLE_AUTH_CLIENT_SECRET"],
    ["GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET"],
  ]) {
    const id = Deno.env.get(idKey)?.trim() ?? "";
    const secret = Deno.env.get(secretKey)?.trim() ?? "";
    if (id.length > 0 && secret.length > 0 && !daftar.some((c) => c.id === id)) {
      daftar.push({ id, secret });
    }
  }
  return daftar;
}

/// Refresh dengan tiap client sampai berhasil. Client berikutnya hanya
/// dicoba bila Google membalas `unauthorized_client` (token diterbitkan
/// client lain); galat lain (mis. `invalid_grant`) langsung dikembalikan.
async function refreshWithAnyClient(
  clients: OAuthClient[],
  refreshToken: string,
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  let result = { ok: false, status: 500, data: {} as Record<string, unknown> };
  for (const client of clients) {
    result = await refreshWithGoogle(client.id, client.secret, refreshToken);
    if (result.ok || result.data["error"] !== "unauthorized_client") break;
  }
  return result;
}

/// Urutan pemilihan token sama dengan aplikasi sebelumnya:
/// 1. token pribadi milik user pemanggil,
/// 2. akun kantor utama (google_email),
/// 3. akun bersama (is_shared_company_account) terbaru.
async function selectTokenRow(
  admin: SupabaseClient,
  authUid: string,
  primaryEmail: string,
): Promise<{ row: TokenRow; source: string } | null> {
  const { data: appUser } = await admin
    .from("users")
    .select("id")
    .eq("auth_uid", authUid)
    .maybeSingle();

  const internalUserId = appUser?.id?.toString() ?? "";
  if (internalUserId.length > 0) {
    const { data } = await admin
      .from("google_account_tokens")
      .select(TOKEN_COLUMNS)
      .eq("user_id", internalUserId)
      .or(
        "is_shared_company_account.is.null,is_shared_company_account.eq.false",
      )
      .order("updated_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();
    if (data) return { row: data as unknown as TokenRow, source: "personal" };
  }

  {
    const { data } = await admin
      .from("google_account_tokens")
      .select(TOKEN_COLUMNS)
      .eq("google_email", primaryEmail)
      .order("updated_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();
    if (data) return { row: data as unknown as TokenRow, source: "primary_email" };
  }

  {
    const { data } = await admin
      .from("google_account_tokens")
      .select(TOKEN_COLUMNS)
      .eq("is_shared_company_account", true)
      .order("updated_at", { ascending: false, nullsFirst: false })
      .limit(1)
      .maybeSingle();
    if (data) return { row: data as unknown as TokenRow, source: "shared_flag" };
  }

  return null;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // Refresh token hanya bisa ditukar oleh client OAuth yang menerbitkannya.
  // Akun yang dihubungkan dari web direktori memakai client Web
  // ("BPS Kota Parepare Web", GOOGLE_AUTH_CLIENT_*); yang dihubungkan dari
  // aplikasi Bolt memakai client Desktop ("Bolt - Backoffice",
  // GOOGLE_CLIENT_*). Keduanya dicoba berurutan.
  const clients = oauthClients();
  if (clients.length === 0) {
    return json(
      {
        error: "missing_google_oauth_config",
        message: "GOOGLE_AUTH_CLIENT_* / GOOGLE_CLIENT_* belum diatur",
      },
      500,
    );
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch (_) {
    return json({ error: "invalid_json_body" }, 400);
  }

  // Mode lama: aplikasi versi lama mengirim refresh_token sendiri.
  // Dipertahankan sampai semua perangkat memakai mode `access_token`.
  const legacyRefreshToken = String(payload["refresh_token"] ?? "").trim();
  if (payload["mode"] !== "access_token") {
    if (legacyRefreshToken.length === 0) {
      return json({ error: "missing_refresh_token" }, 400);
    }
    const result = await refreshWithAnyClient(clients, legacyRefreshToken);
    if (!result.ok) {
      console.error("google-drive-refresh legacy: refresh gagal", {
        status: result.status,
        details: result.data,
      });
      return json(
        {
          error: "google_refresh_failed",
          status: result.status,
          details: result.data,
        },
        result.status,
      );
    }
    return json({
      access_token: String(result.data["access_token"] ?? ""),
      expires_in: Number(result.data["expires_in"] ?? 3600),
      token_type: String(result.data["token_type"] ?? "Bearer"),
    });
  }

  // Mode baru: token dibaca & disimpan di server dengan service role,
  // refresh_token tidak pernah dikirim ke aplikasi.
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await caller.auth.getUser();
  if (userError || !userData?.user) {
    return json({ error: "unauthorized", message: "Sesi login tidak valid" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const primaryEmail =
    Deno.env.get("GOOGLE_DRIVE_PRIMARY_EMAIL")?.trim() || "bps737273@gmail.com";

  const selected = await selectTokenRow(admin, userData.user.id, primaryEmail);
  if (!selected) {
    console.error("google-drive-refresh: tidak ada token Google Drive", {
      auth_uid: userData.user.id,
    });
    return json(
      {
        error: "no_google_token",
        message: "Belum ada akun Google Drive yang terhubung.",
      },
      404,
    );
  }

  const { row, source } = selected;
  const meta = {
    source,
    token_id: row.id,
    google_email: row.google_email,
    is_shared_company_account: row.is_shared_company_account,
  };

  const forceRefresh = payload["force_refresh"] === true;
  const expiryMs = row.token_expiry ? Date.parse(row.token_expiry) : NaN;
  const stillValid = !Number.isNaN(expiryMs) &&
    expiryMs - Date.now() > EXPIRY_BUFFER_MS;

  if (!forceRefresh && stillValid && (row.access_token ?? "").length > 0) {
    return json({
      ...meta,
      access_token: row.access_token,
      expires_at: new Date(expiryMs).toISOString(),
      refreshed: false,
    });
  }

  const refreshToken = (row.refresh_token ?? "").trim();
  if (refreshToken.length === 0) {
    console.error("google-drive-refresh: refresh_token kosong", meta);
    return json(
      {
        ...meta,
        error: "missing_refresh_token",
        message:
          "Token Google Drive kadaluarsa dan tidak punya refresh token. " +
          "Mohon hubungkan ulang akun Google Drive.",
      },
      409,
    );
  }

  const result = await refreshWithAnyClient(clients, refreshToken);
  if (!result.ok) {
    console.error("google-drive-refresh: refresh ditolak Google", {
      ...meta,
      status: result.status,
      details: result.data,
    });
    const googleError = String(result.data["error"] ?? "unknown");
    return json(
      {
        ...meta,
        error: "google_refresh_failed",
        google_error: googleError,
        google_error_description: result.data["error_description"] ?? null,
        status: result.status,
        message:
          `Google menolak refresh token (${googleError}). ` +
          "Mohon hubungkan ulang akun Google Drive.",
      },
      502,
    );
  }

  const accessToken = String(result.data["access_token"] ?? "");
  const expiresIn = Number(result.data["expires_in"] ?? 3600);
  const expiresAt = new Date(Date.now() + expiresIn * 1000).toISOString();

  const update: Record<string, unknown> = {
    access_token: accessToken,
    token_expiry: expiresAt,
    updated_at: new Date().toISOString(),
  };
  // Google kadang merotasi refresh token; simpan bila ada yang baru.
  const newRefreshToken = String(result.data["refresh_token"] ?? "").trim();
  if (newRefreshToken.length > 0) update.refresh_token = newRefreshToken;

  const { error: updateError } = await admin
    .from("google_account_tokens")
    .update(update)
    .eq("id", row.id);
  if (updateError) {
    // Token tetap bisa dipakai walau gagal disimpan.
    console.error("google-drive-refresh: gagal simpan token", {
      ...meta,
      error: updateError.message,
    });
  }

  return json({
    ...meta,
    access_token: accessToken,
    expires_at: expiresAt,
    refreshed: true,
  });
});
