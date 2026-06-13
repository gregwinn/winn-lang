-module(winn_auth).
-export([middleware/3, register/2, login/2, current_user/1,
         refresh/1, logout/1, write_session/2, clear_session/1,
         request_email_verification/1, verify_email/1,
         request_password_reset/1, reset_password/2]).
-export([csrf_valid/3]).  %% exported for tests

%% This module is the `Auth` Winn module (winn_codegen_resolve maps Auth -> winn_auth)
%% and also the JWT Bearer middleware used by winn_router.
%%
%% Service API (the `Auth.*` calls):
%%   Auth.register(email, password) -> {ok, user} | {error, reason}
%%   Auth.login(email, password)    -> {ok, %{user: u, access_token: a, refresh_token: r}}
%%                                     | {error, :invalid_credentials}
%%   Auth.refresh(refresh_token)    -> {ok, %{access_token: a, refresh_token: r2}}
%%                                     | {error, :invalid_token}
%%   Auth.logout(refresh_token)     -> :ok
%%   Auth.current_user(conn)        -> {ok, user} | {error, :unauthenticated}
%%   Auth.write_session(conn, tokens) -> conn   (cookie strategy: set auth cookies)
%%   Auth.clear_session(conn)         -> conn   (cookie strategy: clear auth cookies)
%%
%% Strategy: the `[:auth]` middleware authenticates via the `Authorization: Bearer`
%% header by default. Set `auth_config` `strategy: :cookie` to instead read the
%% access JWT from an HttpOnly cookie and enforce double-submit CSRF on unsafe
%% methods. `write_session`/`clear_session` set/clear those cookies on login/logout.
%%
%% Tokens: the access token is a short-lived JWT (stateless). The refresh token is
%% a long-lived, opaque, high-entropy random string; only its SHA-256 hash is
%% stored (in the `auth_tokens` table), so a DB leak doesn't hand over live
%% sessions. Refresh rotates (old row deleted, new issued); logout deletes the row.
%%
%% Conventions (overridable via Config, see helpers at the bottom):
%%   - User schema module defaults to `user` (a `schema "users"` with at least
%%     `email`, `password_hash`; `verified` and `created_at` recommended).
%%   - Token schema module defaults to `auth_token` (a `schema "auth_tokens"` with
%%     `user_id`, `token_hash`, `expires_at`).
%%   - JWT signing secret read from Config: Config.put(:auth, :secret, "...").
%%   - Access-token TTL  from Config `auth.access_token_ttl`  (seconds, default 3600).
%%   - Refresh-token TTL from Config `auth.refresh_token_ttl` (seconds, default 30d).

-define(DEFAULT_ACCESS_TTL, 3600).
-define(DEFAULT_REFRESH_TTL, 2592000). %% 30 days
-define(REFRESH_TOKEN_BYTES, 32).

%% Cookie-strategy names (stateless JWT-in-cookie + double-submit CSRF).
-define(ACCESS_COOKIE,  <<"access_token">>).
-define(REFRESH_COOKIE, <<"refresh_token">>).
-define(CSRF_COOKIE,    <<"csrf">>).
-define(CSRF_HEADER,    <<"x-csrf-token">>).

%% A valid-format PHC string used to keep login timing uniform when the email is
%% unknown, so an attacker can't distinguish "no such user" from "wrong password"
%% by response time. The salt/hash are 16/32 zero bytes — it never matches.
-define(DUMMY_PW_HASH,
        <<"$pbkdf2-sha256$i=600000$AAAAAAAAAAAAAAAAAAAAAA==$"
          "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=">>).

%% ── Service API ──────────────────────────────────────────────────────────────

%% Register a new user. Hashes the password and inserts via the repo. Returns the
%% created user (without the password hash). Fails with `email_taken` if the email
%% already exists. A unique index on `email` is the real guard against the
%% check-then-insert race; this check just gives a clean error on the common path.
register(Email, Password) when is_binary(Email), is_binary(Password) ->
    Repo   = repo_mod(),
    Schema = user_schema(),
    case Repo:get(Schema, email, Email) of
        {ok, _Existing} ->
            {error, email_taken};
        {error, not_found} ->
            Attrs = #{email => Email,
                      password_hash => winn_crypto:hash_password(Password),
                      verified => false,
                      created_at => os:system_time(second)},
            case Repo:insert(Schema, Attrs) of
                {ok, User} ->
                    %% Optionally email a verification link (auth.verify_email).
                    _ = maybe_send_verification(Email),
                    {ok, sanitize(User)};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Authenticate an email/password pair. On success returns the user plus a signed
%% short-lived access JWT and a rotating refresh token. Wrong password and unknown
%% email both return the same `invalid_credentials` error (and take similar time)
%% — no user enumeration.
login(Email, Password) when is_binary(Email), is_binary(Password) ->
    Repo   = repo_mod(),
    Schema = user_schema(),
    case Repo:get(Schema, email, Email) of
        {ok, User} ->
            Hash = maps:get(password_hash, User, <<>>),
            case winn_crypto:verify_password(Password, Hash) of
                true ->
                    case issue_tokens(User) of
                        {ok, Tokens}    -> {ok, Tokens#{user => sanitize(User)}};
                        {error, Reason} -> {error, Reason}
                    end;
                false ->
                    {error, invalid_credentials}
            end;
        {error, not_found} ->
            _ = winn_crypto:verify_password(Password, ?DUMMY_PW_HASH),
            {error, invalid_credentials};
        {error, _Reason} ->
            {error, invalid_credentials}
    end.

%% Exchange a valid refresh token for a fresh access token and a rotated refresh
%% token. The presented token is invalidated (single use); an expired, unknown, or
%% already-rotated token returns `invalid_token`.
refresh(RawToken) when is_binary(RawToken) ->
    case consume_token(RawToken, refresh) of
        {ok, Token} ->
            case load_user(maps:get(user_id, Token, undefined)) of
                {ok, User} -> issue_tokens(User);
                {error, _} -> {error, invalid_token}
            end;
        Error ->
            Error
    end;
refresh(_) ->
    {error, invalid_token}.

%% Revoke a refresh token (log out). Idempotent — an unknown token is still `:ok`.
logout(RawToken) when is_binary(RawToken) ->
    Repo   = repo_mod(),
    Schema = token_schema(),
    case Repo:get(Schema, token_hash, hash_token(RawToken)) of
        {ok, Token} -> _ = delete_token(Token), ok;
        {error, _}  -> ok
    end;
logout(_) ->
    ok.

%% Resolve the authenticated user from a conn. The Bearer middleware attaches the
%% verified JWT claims (binary keys) under `claims`; we load the user by `user_id`.
current_user(Conn) when is_map(Conn) ->
    case maps:get(claims, Conn, undefined) of
        Claims when is_map(Claims) ->
            case maps:get(<<"user_id">>, Claims, undefined) of
                undefined ->
                    {error, unauthenticated};
                UserId ->
                    Repo   = repo_mod(),
                    Schema = user_schema(),
                    case Repo:get(Schema, UserId) of
                        {ok, User} -> {ok, sanitize(User)};
                        {error, _} -> {error, unauthenticated}
                    end
            end;
        _ ->
            {error, unauthenticated}
    end;
current_user(_) ->
    {error, unauthenticated}.

%% ── Account recovery (email verification + password reset) ───────────────────

%% Email a verification link for an address. Always `:ok` — never reveals whether
%% the address is registered. (register/2 calls this when `auth.verify_email` is on.)
request_email_verification(Email) when is_binary(Email) ->
    Repo = repo_mod(),
    case Repo:get(user_schema(), email, Email) of
        {ok, User} ->
            case create_token(user_id(User), verify_email, verify_ttl()) of
                {ok, Raw} -> send_link(Email, <<"Verify your email">>, verify_url(), Raw);
                _         -> ok
            end;
        _ ->
            ok
    end,
    ok.

%% Consume an email-verification token and mark its user verified.
verify_email(Token) when is_binary(Token) ->
    case consume_token(Token, verify_email) of
        {ok, T} ->
            case load_user(maps:get(user_id, T, undefined)) of
                {ok, User} -> update_user(User#{verified => true});
                {error, _} -> {error, invalid_token}
            end;
        Error ->
            Error
    end;
verify_email(_) ->
    {error, invalid_token}.

%% Begin a password reset. Always `:ok` (no user enumeration); emails a reset link
%% only if the address exists.
request_password_reset(Email) when is_binary(Email) ->
    Repo = repo_mod(),
    case Repo:get(user_schema(), email, Email) of
        {ok, User} ->
            case create_token(user_id(User), reset_password, reset_ttl()) of
                {ok, Raw} -> send_link(Email, <<"Reset your password">>, reset_url(), Raw);
                _         -> ok
            end;
        _ ->
            ok
    end,
    ok.

%% Complete a password reset with a valid (single-use, unexpired) token.
reset_password(Token, NewPassword) when is_binary(Token), is_binary(NewPassword) ->
    case consume_token(Token, reset_password) of
        {ok, T} ->
            case load_user(maps:get(user_id, T, undefined)) of
                {ok, User} ->
                    update_user(User#{password_hash => winn_crypto:hash_password(NewPassword)});
                {error, _} ->
                    {error, invalid_token}
            end;
        Error ->
            Error
    end;
reset_password(_, _) ->
    {error, invalid_token}.

%% ── Session cookies (cookie strategy) ────────────────────────────────────────

%% Set the auth cookies from a login/refresh token result, for the `:cookie`
%% strategy. The access (and refresh) tokens go in HttpOnly cookies the browser
%% sends automatically; a separate non-HttpOnly `csrf` cookie is the double-submit
%% token the frontend echoes in the `X-CSRF-Token` header. Returns the conn.
write_session(Conn, Tokens) when is_map(Tokens) ->
    Access  = maps:get(access_token, Tokens, <<>>),
    Conn1   = winn_server:set_cookie(Conn, ?ACCESS_COOKIE, Access, http_only_opts()),
    Conn2   = case maps:get(refresh_token, Tokens, undefined) of
                  R when is_binary(R) ->
                      winn_server:set_cookie(Conn1, ?REFRESH_COOKIE, R, http_only_opts());
                  _ ->
                      Conn1
              end,
    winn_server:set_cookie(Conn2, ?CSRF_COOKIE, gen_token(16), csrf_opts()).

%% Clear the auth cookies (log out of a cookie session).
clear_session(Conn) ->
    Expire = #{path => <<"/">>, max_age => 0},
    C1 = winn_server:set_cookie(Conn, ?ACCESS_COOKIE,  <<>>, Expire),
    C2 = winn_server:set_cookie(C1,   ?REFRESH_COOKIE, <<>>, Expire),
    winn_server:set_cookie(C2, ?CSRF_COOKIE, <<>>, Expire).

%% ── Middleware ───────────────────────────────────────────────────────────────

%% Auth middleware. In the default `:bearer` strategy it reads the access JWT from
%% the `Authorization: Bearer` header; in `:cookie` strategy it reads it from the
%% access cookie and enforces double-submit CSRF on unsafe methods. Verified claims
%% are attached to the conn. 401 on missing/invalid token, 403 on CSRF failure,
%% unless the path is excluded.
middleware(Conn, Next, Config) ->
    Path = maps:get(path, Conn),
    case is_excluded(Path, maps:get(exclude, Config, [])) of
        true ->
            Next(Conn);
        false ->
            case authenticate(Conn, Config, strategy(Config)) of
                {ok, Conn2}      -> Next(Conn2);
                {error, csrf}    -> forbidden(Conn);
                {error, _Reason} -> unauthorized(Conn)
            end
    end.

strategy(Config) ->
    case maps:get(strategy, Config, bearer) of
        cookie -> cookie;
        _      -> bearer
    end.

authenticate(Conn, Config, bearer) ->
    case extract_bearer(Conn) of
        {ok, Token} -> verify_token(Conn, Token, Config);
        Error       -> Error
    end;
authenticate(Conn, Config, cookie) ->
    case csrf_ok(Conn) of
        true ->
            case extract_cookie_token(Conn) of
                {ok, Token} -> verify_token(Conn, Token, Config);
                Error       -> Error
            end;
        false ->
            {error, csrf}
    end.

verify_token(Conn, Token, Config) ->
    Secret = maps:get(secret, Config, <<>>),
    case winn_jwt:verify(Token, Secret) of
        {ok, Claims}    -> {ok, Conn#{claims => Claims}};
        {error, Reason} -> {error, Reason}
    end.

%% ── Internal ────────────────────────────────────────────────────────────────

%% Issue an access + refresh token pair for a user.
issue_tokens(User) ->
    case issue_access_token(User) of
        {ok, Access} ->
            case issue_refresh_token(user_id(User)) of
                {ok, Refresh}   -> {ok, #{access_token  => Access,
                                          refresh_token => Refresh}};
                {error, Reason} -> {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Sign an access token for a user. Subject is the user id; email is included for
%% convenience. Fails if no signing secret is configured.
issue_access_token(User) ->
    case secret() of
        nil ->
            {error, missing_secret};
        Secret ->
            Exp = os:system_time(second) + access_ttl(),
            Claims = #{<<"user_id">> => user_id(User),
                       <<"email">>   => maps:get(email, User, null),
                       <<"exp">>     => Exp},
            {ok, winn_jwt:sign(Claims, Secret)}
    end.

issue_refresh_token(UserId) ->
    create_token(UserId, refresh, refresh_ttl()).

%% Create and store a single-use token in the `auth_tokens` table for `Purpose`
%% (refresh | verify_email | reset_password). Returns the raw token (shown once);
%% only its hash is persisted.
create_token(UserId, Purpose, Ttl) ->
    Repo  = repo_mod(),
    Raw   = gen_token(?REFRESH_TOKEN_BYTES),
    Attrs = #{user_id    => UserId,
              token_hash => hash_token(Raw),
              purpose    => Purpose,
              expires_at => os:system_time(second) + Ttl,
              created_at => os:system_time(second)},
    case Repo:insert(token_schema(), Attrs) of
        {ok, _}         -> {ok, Raw};
        {error, Reason} -> {error, Reason}
    end.

%% Look up a token by hash, consume it (single-use: always deleted on
%% presentation), and validate its purpose + expiry. `Purpose` must match so a
%% verify/reset link can't be redeemed at /auth/refresh and vice versa.
consume_token(RawToken, Purpose) ->
    Repo = repo_mod(),
    case Repo:get(token_schema(), token_hash, hash_token(RawToken)) of
        {ok, Token} ->
            _ = delete_token(Token),
            PurposeOk = maps:get(purpose, Token, refresh) =:= Purpose,
            NotExpired = maps:get(expires_at, Token, 0) > os:system_time(second),
            case PurposeOk andalso NotExpired of
                true  -> {ok, Token};
                false -> {error, invalid_token}
            end;
        {error, _} ->
            {error, invalid_token}
    end.

%% N bytes of entropy as a hex string (refresh / CSRF / recovery tokens).
gen_token(N) ->
    binary:encode_hex(crypto:strong_rand_bytes(N)).

%% Tokens are high-entropy random values, so a fast SHA-256 (not PBKDF2) is the
%% right at-rest hash; it also makes lookup-by-hash a single indexed query.
hash_token(Raw) ->
    winn_crypto:hash(sha256, Raw).

delete_token(Token) ->
    Repo = repo_mod(),
    Repo:delete(Token#{'__schema__' => token_schema()}).

%% Persist a changed user record (verify flag / new password hash).
update_user(User) ->
    Repo = repo_mod(),
    case Repo:update(User#{'__schema__' => user_schema()}) of
        {ok, Updated}   -> {ok, sanitize(Updated)};
        {error, Reason} -> {error, Reason}
    end.

%% Email a link of the form `<UrlPrefix><raw token>` (best-effort).
send_link(To, Subject, UrlPrefix, Token) ->
    Body = <<"Open this link to continue:\n\n", UrlPrefix/binary, Token/binary, "\n">>,
    _ = winn_mailer:send(To, Subject, Body),
    ok.

maybe_send_verification(Email) ->
    case winn_config:get(auth, verify_email) of
        true -> request_email_verification(Email);
        _    -> ok
    end.

load_user(undefined) -> {error, not_found};
load_user(UserId) ->
    Repo = repo_mod(),
    Repo:get(user_schema(), UserId).

%% Subject id for tokens/claims — the row id, falling back to email.
user_id(User) -> maps:get(id, User, maps:get(email, User, null)).

%% Strip the password hash before returning a user to callers.
sanitize(User) when is_map(User) -> maps:remove(password_hash, User);
sanitize(User) -> User.

%% Repo module — defaults to winn_repo; overridable via Config (mainly for tests).
repo_mod() ->
    case winn_config:get(auth, repo_module) of
        nil -> winn_repo;
        Mod -> Mod
    end.

%% User schema module — defaults to `user` (a `schema "users"` block).
user_schema() ->
    case winn_config:get(auth, user_schema) of
        nil    -> user;
        Schema -> Schema
    end.

%% Refresh-token schema module — defaults to `auth_token` (a `schema "auth_tokens"`).
token_schema() ->
    case winn_config:get(auth, token_schema) of
        nil    -> auth_token;
        Schema -> Schema
    end.

refresh_ttl() -> config_int(refresh_token_ttl, ?DEFAULT_REFRESH_TTL).
verify_ttl()  -> config_int(verify_token_ttl, 86400).  %% 24h
reset_ttl()   -> config_int(reset_token_ttl, 3600).    %% 1h

%% URL prefixes the recovery emails point at; the raw token is appended.
verify_url() -> config_bin(verify_url, <<"http://localhost:4000/auth/verify?token=">>).
reset_url()  -> config_bin(reset_url,  <<"http://localhost:4000/auth/reset?token=">>).

config_int(Key, Default) ->
    case winn_config:get(auth, Key) of
        N when is_integer(N) -> N;
        _                    -> Default
    end.

config_bin(Key, Default) ->
    case winn_config:get(auth, Key) of
        B when is_binary(B) -> B;
        _                   -> Default
    end.

%% JWT signing secret (binary) from Config, or nil if unset.
secret() ->
    winn_config:get(auth, secret).

access_ttl() -> config_int(access_token_ttl, ?DEFAULT_ACCESS_TTL).

extract_bearer(Conn) ->
    Req = maps:get(req, Conn),
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Bearer ", Token/binary>> ->
            {ok, Token};
        _ ->
            {error, no_token}
    end.

extract_cookie_token(Conn) ->
    case winn_server:get_cookie(Conn, ?ACCESS_COOKIE) of
        nil   -> {error, no_token};
        Token -> {ok, Token}
    end.

%% Double-submit CSRF: safe methods pass; unsafe methods require the X-CSRF-Token
%% header to match the `csrf` cookie.
csrf_ok(Conn) ->
    Req = maps:get(req, Conn),
    HeaderToken = case cowboy_req:header(?CSRF_HEADER, Req) of
                      undefined -> nil;
                      V         -> V
                  end,
    csrf_valid(maps:get(method, Conn), HeaderToken, winn_server:get_cookie(Conn, ?CSRF_COOKIE)).

%% Pure CSRF decision (exported for tests).
csrf_valid(Method, HeaderToken, CookieToken) ->
    case is_safe_method(Method) of
        true  -> true;
        false -> is_binary(HeaderToken) andalso is_binary(CookieToken)
                   andalso ct_equal(HeaderToken, CookieToken)
    end.

is_safe_method(M) -> lists:member(M, [<<"GET">>, <<"HEAD">>, <<"OPTIONS">>]).

%% Constant-time equality.
ct_equal(A, B) when byte_size(A) =/= byte_size(B) -> false;
ct_equal(A, B) -> ct_equal(A, B, 0).
ct_equal(<<>>, <<>>, Acc) -> Acc =:= 0;
ct_equal(<<X, RA/binary>>, <<Y, RB/binary>>, Acc) -> ct_equal(RA, RB, Acc bor (X bxor Y)).

%% HttpOnly cookie carrying a token the browser sends but JS can't read.
http_only_opts() ->
    #{http_only => true, secure => true, same_site => <<"Lax">>, path => <<"/">>}.

%% CSRF cookie is readable by JS (so it can echo it in the header).
csrf_opts() ->
    #{http_only => false, secure => true, same_site => <<"Lax">>, path => <<"/">>}.

unauthorized(Conn) ->
    winn_server:json(Conn, #{error => <<"unauthorized">>}, 401).

forbidden(Conn) ->
    winn_server:json(Conn, #{error => <<"forbidden">>}, 403).

is_excluded(_Path, []) ->
    false;
is_excluded(Path, [Pattern | Rest]) ->
    PatternBin = to_binary(Pattern),
    case match_path_pattern(Path, PatternBin) of
        true  -> true;
        false -> is_excluded(Path, Rest)
    end.

match_path_pattern(Path, Pattern) ->
    case binary:last(Pattern) of
        $* ->
            Prefix = binary:part(Pattern, 0, byte_size(Pattern) - 1),
            binary:match(Path, Prefix) =:= {0, byte_size(Prefix)};
        _ ->
            Path =:= Pattern
    end.

to_binary(V) when is_binary(V) -> V;
to_binary(V) when is_list(V)   -> list_to_binary(V).
