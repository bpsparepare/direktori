import argparse
import asyncio
import json
import websockets

WS_URL = "ws://localhost:9222/devtools/page/BAA28578A0B762630AF9BF12325F9989"

TARGET_PATHS = [
    "/dirgc/konfirmasi-user",
    "/direktori-usaha/data-gc-card",
]

GC_TOKEN = ""
CSRF_TOKEN = ""


def _is_target_url(url: str) -> bool:
    return any(p in url for p in TARGET_PATHS)


async def sniff_network():
    async with websockets.connect(WS_URL) as ws:
        await ws.send(
            json.dumps(
                {
                    "id": 1,
                    "method": "Network.enable",
                    "params": {},
                },
            ),
        )

        print("✅ Network.enable dikirim, tunggu aktivitas dari WebView...")

        pending_bodies = set()

        while True:
            msg = await ws.recv()
            data = json.loads(msg)

            method = data.get("method")
            params = data.get("params", {})

            if method == "Network.requestWillBeSent":
                req = params["request"]
                url = req["url"]
                if _is_target_url(url):
                    print("\n================ REQUEST ==================")
                    print("URL    :", url)
                    print("Method :", req.get("method"))
                    print(
                        "Headers:",
                        json.dumps(req.get("headers", {}), indent=2),
                    )
                    if "postData" in req:
                        print("Body   :", req["postData"])

            if method == "Network.responseReceived":
                resp = params["response"]
                url = resp["url"]
                if _is_target_url(url):
                    request_id = params["requestId"]
                    print("\n================ RESPONSE HEADERS =========")
                    print("URL    :", url)
                    print("Status :", resp.get("status"))
                    print(
                        "Headers:",
                        json.dumps(resp.get("headers", {}), indent=2),
                    )

                    await ws.send(
                        json.dumps(
                            {
                                "id": 1000,
                                "method": "Network.getResponseBody",
                                "params": {"requestId": request_id},
                            },
                        ),
                    )
                    pending_bodies.add(1000)

            if data.get("id") == 1000 and "result" in data:
                body = data["result"].get("body", "")
                print("\n================ RESPONSE BODY ============")
                print(body[:2000])
                if 1000 in pending_bodies:
                    pending_bodies.remove(1000)


async def konfirmasi_user_via_webview(
    perusahaan_id: str,
    latitude: str,
    longitude: str,
    hasil_gc: str,
    gc_token: str | None = None,
    csrf_token: str | None = None,
    ws_url: str = WS_URL,
) -> dict | None:
    global GC_TOKEN, CSRF_TOKEN

    token_gc = gc_token if gc_token is not None else GC_TOKEN
    token_csrf = csrf_token if csrf_token is not None else CSRF_TOKEN

    async with websockets.connect(ws_url) as ws:
        await ws.send(
            json.dumps(
                {
                    "id": 1,
                    "method": "Network.enable",
                    "params": {},
                },
            ),
        )
        await ws.send(
            json.dumps(
                {
                    "id": 2,
                    "method": "Runtime.enable",
                    "params": {},
                },
            ),
        )

        payload = {
            "perusahaan_id": perusahaan_id,
            "latitude": latitude,
            "longitude": longitude,
            "hasilgc": hasil_gc,
            "gc_token": token_gc,
            "_token": token_csrf,
        }

        expression = (
            "(function() {{"
            "const p = {payload};"
            "const params = new URLSearchParams();"
            "params.set('perusahaan_id', p.perusahaan_id);"
            "params.set('latitude', p.latitude);"
            "params.set('longitude', p.longitude);"
            "params.set('hasilgc', p.hasilgc);"
            "params.set('gc_token', p.gc_token);"
            "params.set('_token', p._token);"
            "return fetch('https://matchapro.web.bps.go.id/dirgc/konfirmasi-user', {{"
            "method: 'POST',"
            "headers: {{"
            "'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',"
            "'X-Requested-With': 'XMLHttpRequest'"
            "}},"
            "body: params.toString(),"
            "}}).then(r => r.text());"
            "}})()"
        ).format(payload=json.dumps(payload))

        await ws.send(
            json.dumps(
                {
                    "id": 3,
                    "method": "Runtime.evaluate",
                    "params": {
                        "expression": expression,
                        "returnByValue": True,
                    },
                },
            ),
        )

        response_text = None

        while True:
            msg = await ws.recv()
            data = json.loads(msg)
            if data.get("id") == 3:
                result = data.get("result", {}).get("result", {})
                response_text = result.get("value")
                break

        if not response_text:
            return None

        try:
            decoded = json.loads(response_text)
        except Exception:
            return {"raw": response_text}

        new_gc_token = decoded.get("new_gc_token")
        if new_gc_token:
            GC_TOKEN = new_gc_token
        if token_csrf:
            CSRF_TOKEN = token_csrf

        return decoded


def konfirmasi_user_via_webview_sync(
    perusahaan_id: str,
    latitude: str,
    longitude: str,
    hasil_gc: str,
    gc_token: str | None = None,
    csrf_token: str | None = None,
    ws_url: str = WS_URL,
) -> dict | None:
    return asyncio.run(
        konfirmasi_user_via_webview(
            perusahaan_id,
            latitude,
            longitude,
            hasil_gc,
            gc_token,
            csrf_token,
            ws_url,
        ),
    )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Helper untuk sniff atau kirim konfirmasi GC via WebView",
    )
    parser.add_argument(
        "--sniff",
        action="store_true",
        help="Mode sniff network WebView",
    )
    parser.add_argument("--perusahaan-id")
    parser.add_argument("--lat")
    parser.add_argument("--lon")
    parser.add_argument("--hasil-gc")
    parser.add_argument("--gc-token")
    parser.add_argument("--csrf-token")
    parser.add_argument("--ws-url", default=WS_URL)

    args = parser.parse_args()

    if args.sniff:
        asyncio.run(sniff_network())
        return

    if not args.perusahaan_id or not args.lat or not args.lon or not args.hasil_gc:
        parser.error(
            "perusahaan-id, lat, lon, hasil-gc wajib diisi jika tidak menggunakan --sniff",
        )

    resp = konfirmasi_user_via_webview_sync(
        args.perusahaan_id,
        args.lat,
        args.lon,
        args.hasil_gc,
        gc_token=args.gc_token,
        csrf_token=args.csrf_token,
        ws_url=args.ws_url,
    )

    print(json.dumps(resp or {}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
