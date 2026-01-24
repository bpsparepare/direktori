from playwright.sync_api import sync_playwright
import sys
import random

user_agan = [
    "Mozilla/5.0 (Linux; Android 16; ONEPLUS 15 Build/SKQ1.211202.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/143.0.7499.192 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; SM-S928B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.88 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; Pixel 8a Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.102 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; POCO X7 Pro Build/UKQ1.231003.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.45 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 16; SM-A556E Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/134.0.6998.88 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; ONEPLUS PJZ110 Build/SKQ1.210216.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.6834.102 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; Redmi Note 14 Pro Build/UKQ1.231003.002; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.127 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 16; Pixel 9 Pro Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/134.0.6998.45 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 14; moto g85 5G Build/S3SGS32.12-78-7; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/131.0.6778.200 Mobile Safari/537.36",
    "Mozilla/5.0 (Linux; Android 15; SM-G991B Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/132.0.6834.88 Mobile Safari/537.36"
]

# Pilih user agent secara acak dari list yang terverifikasi
user_agents = random.choice(user_agan)

# Reuse a single Playwright instance to avoid starting/stopping inside runtime
_PW = None
def _get_playwright():
    global _PW
    if _PW is None:
        _PW = sync_playwright().start()
    return _PW

def _stop_playwright():
    global _PW
    try:
        if _PW is not None:
            _PW.stop()
            _PW = None
    except Exception:
        pass

def login_with_sso(username, password, otp_code=None):
    """Lakukan login SSO ke MatchaPro dan kembalikan objek halaman jika berhasil."""
    pw = _get_playwright()
    browser = pw.chromium.launch(headless=False)  # Set to True for headless
    
    # Emulate mobile to avoid "Not Authorized" / "Akses lewat matchapro mobile aja"
    context = browser.new_context(
        user_agent=user_agents,
        viewport={"width": 412, "height": 915},
        is_mobile=True,
        has_touch=True,
        extra_http_headers={
            "x-requested-with": "com.matchapro.app",
            "sec-ch-ua": "\"Android WebView\";v=\"143\", \"Chromium\";v=\"143\", \"Not A(Brand\";v=\"24\"",
            "sec-ch-ua-mobile": "?1",
            "sec-ch-ua-platform": "\"Android\""
        }
    )
    page = context.new_page()
    
    # Tambahkan script untuk mengubah navigator properties agar lebih mirip mobile
    page.add_init_script("""
        Object.defineProperty(navigator, 'platform', {
            get: function() { return 'Linux armv8l'; }
        });
        Object.defineProperty(navigator, 'maxTouchPoints', {
            get: function() { return 5; }
        });
    """)

    try:
        # Navigasi ke halaman login
        page.goto("https://matchapro.web.bps.go.id/login")

        # Klik tombol login SSO
        page.click('#login-sso')

        # Tunggu navigasi ke halaman SSO
        page.wait_for_load_state('networkidle')

        # Sekarang di halaman SSO, isi username dan password
        page.fill('input[name="username"]', username)
        page.fill('input[name="password"]', password)

        # Klik tombol submit
        page.click('input[type="submit"]')

        # Tunggu navigasi
        page.wait_for_load_state('networkidle')

        # Cek apakah OTP diperlukan (TOTP)
        try:
            otp_input = page.locator('input[name="otp"]').first
            if otp_input.is_visible(timeout=5000):
                if otp_code is None:
                    otp_code = input("Masukkan kode OTP: ")
                otp_input.fill(otp_code)
                page.click('input[type="submit"]')  # Submit OTP
                page.wait_for_load_state('networkidle')
        except:
            pass  # Tidak perlu OTP

        # Tunggu hingga URL berubah ke matchapro
        page.wait_for_url("https://matchapro.web.bps.go.id/**", timeout=50000)

        # Cek apakah login berhasil
        current_url = page.url
        if "matchapro.web.bps.go.id" in current_url and "login" not in current_url:
            # Login berhasil, extract data untuk Flutter
            import json
            
            # 1. Get Cookies
            cookies = context.cookies()
            cookie_dict = {c['name']: c['value'] for c in cookies}
            cookie_str = "; ".join([f"{c['name']}={c['value']}" for c in cookies])
            
            # 2. Get Tokens via JS
            tokens = page.evaluate('''() => {
                let gc_token = '';
                let csrf_token = '';
                let user_name = '';
                
                try {
                    // Try regex first
                    let match = document.body.innerHTML.match(/let\s+gcSubmitToken\s*=\s*(['"])([^'"]+)\1/);
                    if (match) gc_token = match[2];
                } catch(e) {}
                
                if (!gc_token) {
                    let el = document.querySelector('input[name="gc_token"]');
                    if (el) gc_token = el.value;
                }
                
                let meta = document.querySelector('meta[name="csrf-token"]');
                if (meta) csrf_token = meta.content;
                if (!csrf_token) {
                    let el = document.querySelector('input[name="_token"]');
                    if (el) csrf_token = el.value;
                }
                
                // Try getting username
                let userEl = document.querySelector('.user-name.fw-bolder') || 
                             document.querySelector('.dropdown-user .username') || 
                             document.querySelector('.user-panel .info p');
                
                if (userEl) {
                    user_name = userEl.innerText.trim();
                    console.log("Found username: " + user_name);
                } else {
                    console.log("Username element not found");
                }
                
                return {gc_token, csrf_token, user_name};
            }''')
            
            # Print log if username found
            if tokens.get('user_name'):
                print(f"Log: Username found: {tokens.get('user_name')}")
            
            result = {
                "status": "success",
                "cookie_header": cookie_str,
                "cookies": cookie_dict,
                "gc_token": tokens.get('gc_token', ''),
                "csrf_token": tokens.get('csrf_token', ''),
                "user_name": tokens.get('user_name', 'Python User'),
                "user_agent": user_agents
            }
            
            # Print JSON specific marker for Flutter to parse
            print("\n---JSON_START---")
            print(json.dumps(result))
            print("---JSON_END---\n")
            
            return page, browser  # Mengembalikan halaman dan browser untuk menjaga sesi
        else:
            print("Login gagal. Periksa kredensial.")
            print(f"Current URL: {current_url}")
            try:
                browser.close()
            except Exception:
                pass
            return None, None

    except Exception as e:
        print(f"Error selama login: {e}")
        try:
            browser.close()
        except Exception:
            pass
        return None, None

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python login.py <username> <password> [otp_code]")
        sys.exit(1)

    username = sys.argv[1]
    password = sys.argv[2]
    otp_code = sys.argv[3] if len(sys.argv) > 3 else None

    page, browser = login_with_sso(username, password, otp_code)
    if page:
        print("Objek halaman diperoleh.")
        try:
            browser.close()
        except Exception:
            pass
    else:
        print("Gagal memperoleh objek halaman.")

    # Stop global Playwright instance on exit
    try:
        _stop_playwright()
    except Exception:
        pass
    
