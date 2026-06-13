# Authentication

Winn ships first-class email/password authentication: secure password hashing,
JWT access tokens, revocable refresh tokens, optional cookie sessions with CSRF,
and account recovery (email verification + password reset). This guide takes you
from zero to working auth endpoints a JavaScript frontend can call.

For the per-function reference see [`Auth`](modules.md#auth) in modules.md and
[`Crypto`](stdlib.md#crypto) / [`Mailer`](stdlib.md#mailer) in stdlib.md.

## Quick start

```sh
winn create auth
```

generates a complete email/password setup:

```
src/models/user.winn                         # User schema (users table)
src/models/auth_token.winn                   # AuthToken schema (auth_tokens table)
db/migrations/<ts>01_create_users.winn       # users table
db/migrations/<ts>02_create_auth_tokens.winn # auth_tokens table (refresh + recovery)
src/controllers/auth_controller.winn         # router: register/login/refresh/logout/verify/forgot/reset/me
```

Then:

1. **Set a signing secret** at startup (e.g. in `main()`):

   ```winn
   Config.put(:auth, :secret, System.get_env("JWT_SECRET"))
   ```

2. **Run the migrations:** `winn migrate`

3. **Mount the controller** and start the server (`Server.start(AuthController, 4000)`).

That's it — you now have these endpoints:

| Method & path        | What it does |
|----------------------|--------------|
| `POST /auth/register`| create a user (hashes the password) |
| `POST /auth/login`   | returns `access_token` + `refresh_token` |
| `POST /auth/refresh` | rotate tokens (single-use refresh) |
| `POST /auth/logout`  | revoke a refresh token |
| `GET  /auth/verify`  | confirm an email-verification token |
| `POST /auth/forgot`  | request a password-reset email |
| `POST /auth/reset`   | set a new password with a reset token |
| `GET  /api/me`       | the authenticated user (protected) |

## How the tokens work

- **Access token** — a short-lived (1h) JWT, signed with your secret. Stateless;
  the `[:auth]` middleware verifies it on protected routes. Sent as
  `Authorization: Bearer <token>`.
- **Refresh token** — a long-lived (30d), opaque, random string. Only its SHA-256
  hash is stored (in `auth_tokens`), so a database leak doesn't expose live
  sessions. Each use **rotates** it (the old one stops working), and logout deletes
  it — that's how sessions are revoked.

Tune lifetimes with `Config.put(:auth, :access_token_ttl, 3600)` /
`Config.put(:auth, :refresh_token_ttl, 2592000)`.

## Frontend example (Bearer)

A minimal single-file client. Open it in a browser served from the same origin as
the API (or enable CORS — see [cross-origin](#cross-origin), below).

```html
<script>
const API = "";  // same origin
let access = localStorage.getItem("access");
let refresh = localStorage.getItem("refresh");

async function api(path, opts = {}) {
  const headers = { "Content-Type": "application/json", ...(opts.headers || {}) };
  if (access) headers.Authorization = `Bearer ${access}`;
  let res = await fetch(API + path, { ...opts, headers });
  if (res.status === 401 && refresh) {        // access token expired → rotate
    const r = await fetch(API + "/auth/refresh", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refresh_token: refresh }),
    });
    if (r.ok) {
      ({ access_token: access, refresh_token: refresh } = await r.json());
      localStorage.setItem("access", access);
      localStorage.setItem("refresh", refresh);
      headers.Authorization = `Bearer ${access}`;
      res = await fetch(API + path, { ...opts, headers });
    }
  }
  return res;
}

async function login(email, password) {
  const res = await fetch(API + "/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  if (!res.ok) throw new Error("login failed");
  ({ access_token: access, refresh_token: refresh } = await res.json());
  localStorage.setItem("access", access);
  localStorage.setItem("refresh", refresh);
}

async function me()     { return (await api("/api/me")).json(); }
async function logout() {
  await api("/auth/logout", { method: "POST", body: JSON.stringify({ refresh_token: refresh }) });
  localStorage.clear(); access = refresh = null;
}
</script>
```

## Cookie sessions (no token in JS)

For same-origin web apps you can keep the token out of JavaScript entirely. Set
`strategy: :cookie` in `auth_config` and have the login handler call
`Auth.write_session`:

```winn
def auth_config()
  %{strategy: :cookie, secret: Config.get(:auth, :secret),
    exclude: ["/auth/login", "/auth/register", "/auth/refresh"]}
end

def login(conn)
  params = Server.body_params(conn)
  match Auth.login(params.email, params.password)
    ok tokens =>
      conn = Auth.write_session(conn, tokens)   # HttpOnly access/refresh + csrf cookies
      Server.json(conn, %{status: "ok"})
    err _ => Server.json(conn, %{error: "invalid login"}, 401)
  end
end
```

The browser sends the cookies automatically. On unsafe requests (POST/PUT/PATCH/
DELETE) the middleware enforces **double-submit CSRF**: the frontend reads the
(non-HttpOnly) `csrf` cookie and echoes it in an `X-CSRF-Token` header.

```js
const csrf = document.cookie.split("; ").find(c => c.startsWith("csrf="))?.split("=")[1];
await fetch("/api/posts", {
  method: "POST",
  headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
  body: JSON.stringify(post),
});
```

See [Cookie sessions & CSRF](modules.md#cookie-sessions--csrf) for the details.

<a name="cross-origin"></a>
### Cross-origin

If the frontend lives on a different origin than the API, add CORS credentials:
set `cors_config` `credentials: true` and a **specific** `origins` (not `*`), and
have the browser send `fetch(..., { credentials: "include" })`. Same-origin apps
need no CORS at all.

## Account recovery

### Email verification

Turn it on and `register/2` emails a verification link:

```winn
Config.put(:auth, :verify_email, true)
Config.put(:auth, :verify_url, "https://myapp.com/auth/verify?token=")
```

The link hits `GET /auth/verify?token=...`, and `Auth.verify_email/1` marks the
user verified. Tokens are single-use and expire (default 24h).

### Password reset

```winn
Config.put(:auth, :reset_url, "https://myapp.com/auth/reset?token=")
```

- `POST /auth/forgot` → `Auth.request_password_reset(email)` emails a link if the
  address exists, and **always responds 200** (no user enumeration).
- `POST /auth/reset` → `Auth.reset_password(token, new_password)` sets the new
  password. Reset tokens are single-use and expire (default 1h).

Both require an email transport — configure [`Mailer`](stdlib.md#mailer):

```winn
Config.put(:mailer, :transport, :http)
Config.put(:mailer, :api_key, System.get_env("SENDGRID_API_KEY"))
Config.put(:mailer, :from, "no-reply@myapp.com")
```

## Security notes

- Passwords are hashed with PBKDF2-HMAC-SHA256 (600k iterations) — never reversible.
- Wrong password and unknown email return the same error in similar time.
- Refresh and recovery tokens are stored hashed and are single-use; recovery tokens
  are purpose-checked, so a verification/reset link can't be redeemed for a session.
- In cookie mode, cookies are `HttpOnly`, `Secure`, `SameSite`, with CSRF on writes.
- Consider adding rate limiting on `/auth/login` and `/auth/forgot` (not built in yet).
