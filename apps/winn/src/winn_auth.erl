-module(winn_auth).
-export([middleware/3, register/2, login/2, current_user/1]).

%% This module is the `Auth` Winn module (winn_codegen_resolve maps Auth -> winn_auth)
%% and also the JWT Bearer middleware used by winn_router.
%%
%% Service API (the `Auth.*` calls):
%%   Auth.register(email, password) -> {ok, user} | {error, reason}
%%   Auth.login(email, password)    -> {ok, %{user: user, access_token: token}}
%%                                     | {error, :invalid_credentials}
%%   Auth.current_user(conn)        -> {ok, user} | {error, :unauthenticated}
%%
%% Conventions (overridable via Config, see helpers at the bottom):
%%   - User schema module defaults to `user` (a `schema "users"` with at least
%%     `email`, `password_hash`; `verified` and `created_at` recommended).
%%   - JWT signing secret read from Config: Config.put(:auth, :secret, "...").
%%   - Access-token TTL from Config `auth.access_token_ttl` (seconds, default 3600).

-define(DEFAULT_ACCESS_TTL, 3600).

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

%% Authenticate an email/password pair. On success returns the user and a signed
%% short-lived access JWT. Wrong password and unknown email both return the same
%% `invalid_credentials` error (and take similar time) — no user enumeration.
login(Email, Password) when is_binary(Email), is_binary(Password) ->
    Repo   = repo_mod(),
    Schema = user_schema(),
    case Repo:get(Schema, email, Email) of
        {ok, User} ->
            Hash = maps:get(password_hash, User, <<>>),
            case winn_crypto:verify_password(Password, Hash) of
                true ->
                    case issue_access_token(User) of
                        {ok, Token}     -> {ok, #{user => sanitize(User),
                                                  access_token => Token}};
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

%% Sign an access token for a user. Subject is the user id; email is included for
%% convenience. Fails if no signing secret is configured.
issue_access_token(User) ->
    case secret() of
        nil ->
            {error, missing_secret};
        Secret ->
            Exp = os:system_time(second) + access_ttl(),
            Claims = #{<<"user_id">> => maps:get(id, User, maps:get(email, User, null)),
                       <<"email">>   => maps:get(email, User, null),
                       <<"exp">>     => Exp},
            {ok, winn_jwt:sign(Claims, Secret)}
    end.

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
