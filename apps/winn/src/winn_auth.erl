-module(winn_auth).
-export([middleware/3, register/2, login/2, current_user/1,
         refresh/1, logout/1]).

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
                {ok, User}      -> {ok, sanitize(User)};
                {error, Reason} -> {error, Reason}
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
    Repo   = repo_mod(),
    Schema = token_schema(),
    case Repo:get(Schema, token_hash, hash_token(RawToken)) of
        {ok, Token} ->
            _ = delete_token(Token),   %% single-use: consume on any presentation
            case maps:get(expires_at, Token, 0) > os:system_time(second) of
                true ->
                    case load_user(maps:get(user_id, Token, undefined)) of
                        {ok, User} -> issue_tokens(User);
                        {error, _} -> {error, invalid_token}
                    end;
                false ->
                    {error, invalid_token}
            end;
        {error, _} ->
            {error, invalid_token}
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

%% ── Middleware ───────────────────────────────────────────────────────────────

%% Auth middleware: extracts Bearer token, validates JWT, adds claims to conn.
%% Returns 401 if token is missing/invalid, unless path is excluded.

middleware(Conn, Next, Config) ->
    Path = maps:get(path, Conn),
    ExcludedPaths = maps:get(exclude, Config, []),
    case is_excluded(Path, ExcludedPaths) of
        true ->
            Next(Conn);
        false ->
            case extract_token(Conn) of
                {ok, Token} ->
                    Secret = maps:get(secret, Config, <<>>),
                    case winn_jwt:verify(Token, Secret) of
                        {ok, Claims} ->
                            Next(Conn#{claims => Claims});
                        {error, _Reason} ->
                            unauthorized(Conn)
                    end;
                {error, _} ->
                    unauthorized(Conn)
            end
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

%% Create and store a refresh token; returns the raw token (shown to the client
%% once). Only the hash is persisted.
issue_refresh_token(UserId) ->
    Repo  = repo_mod(),
    Raw   = gen_refresh_token(),
    Attrs = #{user_id    => UserId,
              token_hash => hash_token(Raw),
              expires_at => os:system_time(second) + refresh_ttl(),
              created_at => os:system_time(second)},
    case Repo:insert(token_schema(), Attrs) of
        {ok, _}         -> {ok, Raw};
        {error, Reason} -> {error, Reason}
    end.

%% High-entropy URL-safe refresh token.
gen_refresh_token() ->
    binary:encode_hex(crypto:strong_rand_bytes(?REFRESH_TOKEN_BYTES)).

%% Refresh tokens are high-entropy random values, so a fast SHA-256 (not PBKDF2)
%% is the right at-rest hash; it also makes lookup-by-hash a single indexed query.
hash_token(Raw) ->
    winn_crypto:hash(sha256, Raw).

delete_token(Token) ->
    Repo = repo_mod(),
    Repo:delete(Token#{'__schema__' => token_schema()}).

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

refresh_ttl() ->
    case winn_config:get(auth, refresh_token_ttl) of
        nil                  -> ?DEFAULT_REFRESH_TTL;
        T when is_integer(T) -> T;
        _                    -> ?DEFAULT_REFRESH_TTL
    end.

%% JWT signing secret (binary) from Config, or nil if unset.
secret() ->
    winn_config:get(auth, secret).

access_ttl() ->
    case winn_config:get(auth, access_token_ttl) of
        nil               -> ?DEFAULT_ACCESS_TTL;
        T when is_integer(T) -> T;
        _                 -> ?DEFAULT_ACCESS_TTL
    end.

extract_token(Conn) ->
    Req = maps:get(req, Conn),
    case cowboy_req:header(<<"authorization">>, Req) of
        <<"Bearer ", Token/binary>> ->
            {ok, Token};
        _ ->
            {error, no_token}
    end.

unauthorized(Conn) ->
    winn_server:json(Conn, #{error => <<"unauthorized">>}, 401).

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
