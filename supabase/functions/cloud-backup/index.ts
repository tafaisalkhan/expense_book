// Supabase Edge Function: cloud-backup
// Authenticates Firebase Auth ID Token, verifies Google Play Subscription ($0.99/mo or $5.99/yr),
// and issues short-lived Signed Upload/Download URLs for `user-backups/<firebase_uid>/latest.zip`.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { createRemoteJWKSet, jwtVerify } from "https://esm.sh/jose@5.9.6";

const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID") ?? "";
const ANDROID_PACKAGE = Deno.env.get("ANDROID_PACKAGE_NAME") ?? "com.myexpense.book";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PLAY_SA_JSON = Deno.env.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON") ?? "";

const ALLOWED_PRODUCTS = new Set(["cloud_backup_monthly_v2", "cloud_backup_monthly", "cloud_backup_yearly"]);
const MONTHLY_MAX_BYTES = 100 * 1024 * 1024; // 100 MB ($0.99/mo)
const YEARLY_MAX_BYTES = 600 * 1024 * 1024;  // 600 MB ($5.99/yr)
const VIP_OWNER_EMAILS = new Set(["muhammadfaysal.khan7@gmail.com"]);

function maxBytesForProduct(productId: string | null | undefined): number {
  return productId === "cloud_backup_yearly" ? YEARLY_MAX_BYTES : MONTHLY_MAX_BYTES;
}
const FIREBASE_JWKS = createRemoteJWKSet(
  new URL("https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"),
);

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function verifyFirebaseUser(authHeader: string | null): Promise<{ uid: string; email: string }> {
  if (!authHeader?.startsWith("Bearer ")) {
    throw new Response(JSON.stringify({ error: "Missing Firebase ID token" }), { status: 401 });
  }
  const token = authHeader.slice(7).trim();
  const { payload } = await jwtVerify(token, FIREBASE_JWKS, {
    issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
    audience: FIREBASE_PROJECT_ID,
  });
  const uid = payload.sub;
  if (!uid) throw new Response(JSON.stringify({ error: "Invalid Firebase token" }), { status: 401 });
  const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : "";
  return { uid, email };
}

function base64UrlEncode(value: string): string {
  return btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getGoogleAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/androidpublisher",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const input = `${header}.${claim}`;
  const pemBody = sa.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, new TextEncoder().encode(input));
  const sig = btoa(String.fromCharCode(...new Uint8Array(sigBuf)))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  const assertion = `${input}.${sig}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error(`Google OAuth token error: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

async function verifyPlaySubscription(productId: string, purchaseToken: string): Promise<{ active: boolean; expiresAt: string }> {
  if (!PLAY_SA_JSON) {
    throw new Error("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON secret is not configured.");
  }
  const sa = JSON.parse(PLAY_SA_JSON);
  const accessToken = await getGoogleAccessToken(sa);
  const url = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${ANDROID_PACKAGE}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${accessToken}` } });
  if (!res.ok) return { active: false, expiresAt: new Date(0).toISOString() };
  const data = await res.json();
  const line = data.lineItems?.[0];
  const expiry = line?.expiryTime ?? new Date(0).toISOString();
  const state = data.subscriptionState ?? "";
  const active = (
    state === "SUBSCRIPTION_STATE_ACTIVE" ||
    state === "SUBSCRIPTION_STATE_IN_GRACE_PERIOD" ||
    state === "SUBSCRIPTION_STATE_CANCELED"
  ) &&
    new Date(expiry).getTime() > Date.now() &&
    ALLOWED_PRODUCTS.has(line?.productId ?? productId);
  return { active, expiresAt: expiry };
}

serve(async (req) => {
  try {
    const { uid, email } = await verifyFirebaseUser(req.headers.get("Authorization"));
    const isVipOwner = VIP_OWNER_EMAILS.has(email);
    const vipExpiresAt = new Date(Date.now() + 3650 * 24 * 3600 * 1000).toISOString();
    const body = await req.json();
    const action = body.action as string;

    if (action === "access") {
      if (isVipOwner) {
        await supabase.from("user_subscriptions").upsert({
          firebase_uid: uid,
          product_id: "cloud_backup_yearly",
          purchase_token: `vip_owner_${uid}`,
          status: "active",
          expires_at: vipExpiresAt,
          updated_at: new Date().toISOString(),
        });
        return Response.json({
          active: true,
          productId: "cloud_backup_yearly",
          expiresAt: vipExpiresAt,
          maxSizeBytes: YEARLY_MAX_BYTES,
          vipOwner: true,
        });
      }
      const productId = body.productId as string | undefined;
      const purchaseToken = body.purchaseToken as string | undefined;
      if (productId && purchaseToken && ALLOWED_PRODUCTS.has(productId)) {
        const verified = await verifyPlaySubscription(productId, purchaseToken);
        await supabase.from("user_subscriptions").upsert({
          firebase_uid: uid,
          product_id: productId,
          purchase_token: purchaseToken,
          status: verified.active ? "active" : "expired",
          expires_at: verified.expiresAt,
          updated_at: new Date().toISOString(),
        });
        return Response.json({
          active: verified.active,
          productId,
          expiresAt: verified.expiresAt,
          maxSizeBytes: maxBytesForProduct(productId),
        });
      }
      const { data: sub } = await supabase
        .from("user_subscriptions")
        .select("*")
        .eq("firebase_uid", uid)
        .maybeSingle();
      const active = !!sub && sub.status === "active" && new Date(sub.expires_at).getTime() > Date.now();
      return Response.json({
        active,
        productId: sub?.product_id ?? null,
        expiresAt: sub?.expires_at ?? null,
        maxSizeBytes: maxBytesForProduct(sub?.product_id),
      });
    }

    if (action === "delete_data") {
      const deletePath = `backups/expense/${uid}/latest.zip`;
      await supabase.storage.from("user-backups").remove([deletePath]);
      await supabase.from("user_backup_metadata").delete().eq("firebase_uid", uid);
      await supabase.from("user_subscriptions").delete().eq("firebase_uid", uid);
      return Response.json({ deleted: true });
    }

    // All storage actions require an active paid subscription (or VIP owner email)
    const { data: sub } = await supabase
      .from("user_subscriptions")
      .select("*")
      .eq("firebase_uid", uid)
      .maybeSingle();
    const active = isVipOwner || (!!sub && sub.status === "active" && new Date(sub.expires_at).getTime() > Date.now());
    if (!active) {
      return new Response(JSON.stringify({ error: "subscription_required", active: false }), { status: 403 });
    }

    const storagePath = `backups/expense/${uid}/latest.zip`;
    const planMaxBytes = isVipOwner ? YEARLY_MAX_BYTES : maxBytesForProduct(sub?.product_id);

    if (action === "upload_url") {
      const requestedBytes = Number(body.sizeBytes ?? 0);
      if (requestedBytes > planMaxBytes) {
        const limitMb = Math.round(planMaxBytes / (1024 * 1024));
        return new Response(
          JSON.stringify({ error: `Backup exceeds your ${limitMb} MB plan limit.`, maxSizeBytes: planMaxBytes }),
          { status: 413 },
        );
      }
      const { data, error } = await supabase.storage
        .from("user-backups")
        .createSignedUploadUrl(storagePath, { upsert: true });
      if (error) throw error;
      return Response.json({ signedUrl: data.signedUrl, path: storagePath, maxSizeBytes: planMaxBytes });
    }

    if (action === "commit_metadata") {
      const sizeBytes = Number(body.sizeBytes ?? 0);
      if (sizeBytes > planMaxBytes) {
        await supabase.storage.from("user-backups").remove([storagePath]);
        const limitMb = Math.round(planMaxBytes / (1024 * 1024));
        return new Response(
          JSON.stringify({ error: `Backup exceeds your ${limitMb} MB plan limit.`, maxSizeBytes: planMaxBytes }),
          { status: 413 },
        );
      }
      await supabase.from("user_backup_metadata").upsert({
        firebase_uid: uid,
        storage_path: storagePath,
        exported_at: body.exportedAt ?? new Date().toISOString(),
        size_bytes: sizeBytes,
        expense_count: Number(body.expenseCount ?? 0),
        updated_at: new Date().toISOString(),
      });
      return Response.json({ ok: true, maxSizeBytes: planMaxBytes });
    }

    if (action === "download_url") {
      const { data, error } = await supabase.storage
        .from("user-backups")
        .createSignedUrl(storagePath, 120);
      if (error) return new Response(JSON.stringify({ error: "object-not-found" }), { status: 404 });
      return Response.json({ signedUrl: data.signedUrl });
    }

    if (action === "metadata") {
      const { data } = await supabase
        .from("user_backup_metadata")
        .select("*")
        .eq("firebase_uid", uid)
        .maybeSingle();
      return Response.json({ metadata: data ?? null });
    }

    return new Response(JSON.stringify({ error: "Unknown action" }), { status: 400 });
  } catch (err) {
    if (err instanceof Response) return err;
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
