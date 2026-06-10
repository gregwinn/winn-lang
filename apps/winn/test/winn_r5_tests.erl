%% winn_r5_tests.erl — R5: Crypto and hashing.

-module(winn_r5_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, RawTokens, _} = winn_lexer:string(Source),
    Tokens = winn_newline_filter:filter(RawTokens),
    {ok, AST}       = winn_parser:parse(Tokens),
    Transformed     = winn_transform:transform(AST),
    [CoreMod]       = winn_codegen:gen(Transformed),
    {ok, ModName, Bin} = compile:forms(CoreMod, [from_core, return_errors]),
    code:purge(ModName),
    {module, ModName} = code:load_binary(ModName, "test", Bin),
    ModName.

%% ── Direct runtime tests ────────────────────────────────────────────────

hash_sha256_test() ->
    Result = winn_crypto:hash(sha256, <<"hello">>),
    ?assert(is_binary(Result)),
    %% SHA256 produces 64 hex chars
    ?assertEqual(64, byte_size(Result)),
    %% Known SHA256 of "hello"
    ?assertEqual(<<"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824">>, Result).

hash_md5_test() ->
    Result = winn_crypto:hash(md5, <<"hello">>),
    ?assertEqual(32, byte_size(Result)),
    ?assertEqual(<<"5d41402abc4b2a76b9719d911017c592">>, Result).

hmac_sha256_test() ->
    Result = winn_crypto:hmac(sha256, <<"secret">>, <<"data">>),
    ?assert(is_binary(Result)),
    ?assertEqual(64, byte_size(Result)).

random_bytes_test() ->
    Bytes = winn_crypto:random_bytes(32),
    ?assertEqual(32, byte_size(Bytes)),
    %% Very unlikely to be all zeros
    ?assertNotEqual(<<0:256>>, Bytes).

random_bytes_uniqueness_test() ->
    A = winn_crypto:random_bytes(16),
    B = winn_crypto:random_bytes(16),
    ?assertNotEqual(A, B).

base64_roundtrip_test() ->
    Original = <<"hello world">>,
    Encoded = winn_crypto:base64_encode(Original),
    Decoded = winn_crypto:base64_decode(Encoded),
    ?assertEqual(Original, Decoded).

base64_known_test() ->
    ?assertEqual(<<"aGVsbG8=">>, winn_crypto:base64_encode(<<"hello">>)).

%% ── Password hashing ────────────────────────────────────────────────────

hash_password_format_test() ->
    Hash = winn_crypto:hash_password(<<"hunter2">>),
    ?assert(is_binary(Hash)),
    %% Self-describing PHC-style string with algorithm + iterations.
    ?assertMatch(<<"$pbkdf2-sha256$i=600000$", _/binary>>, Hash).

hash_password_roundtrip_test() ->
    Hash = winn_crypto:hash_password(<<"correct horse">>),
    ?assert(winn_crypto:verify_password(<<"correct horse">>, Hash)).

verify_password_wrong_test() ->
    Hash = winn_crypto:hash_password(<<"hunter2">>),
    ?assertNot(winn_crypto:verify_password(<<"hunter3">>, Hash)),
    ?assertNot(winn_crypto:verify_password(<<"">>, Hash)).

hash_password_salted_test() ->
    %% Same password hashed twice yields different strings (random salt),
    %% but both verify.
    A = winn_crypto:hash_password(<<"same">>),
    B = winn_crypto:hash_password(<<"same">>),
    ?assertNotEqual(A, B),
    ?assert(winn_crypto:verify_password(<<"same">>, A)),
    ?assert(winn_crypto:verify_password(<<"same">>, B)).

verify_password_malformed_test() ->
    %% Garbage / non-PHC input returns false, never crashes.
    ?assertNot(winn_crypto:verify_password(<<"pw">>, <<"not-a-hash">>)),
    ?assertNot(winn_crypto:verify_password(<<"pw">>, <<"$pbkdf2-sha256$i=x$bad$bad">>)),
    ?assertNot(winn_crypto:verify_password(<<"pw">>, <<>>)),
    ?assertNot(winn_crypto:verify_password(<<"pw">>, not_a_binary)).

%% ── End-to-end tests ────────────────────────────────────────────────────

e2e_hash_test() ->
    Src = "module CryptoHash\n  def run()\n    Crypto.hash(:sha256, \"test\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    Result = Mod:run(),
    ?assertEqual(64, byte_size(Result)).

e2e_random_bytes_test() ->
    Src = "module CryptoRand\n  def run()\n    Crypto.random_bytes(16)\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(16, byte_size(Mod:run())).

e2e_base64_test() ->
    Src = "module CryptoB64\n  def run()\n    Crypto.base64_encode(\"hello\")\n  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertEqual(<<"aGVsbG8=">>, Mod:run()).

e2e_password_roundtrip_test() ->
    Src = "module CryptoPw\n"
          "  def run()\n"
          "    hash = Crypto.hash_password(\"s3cret\")\n"
          "    Crypto.verify_password(\"s3cret\", hash)\n"
          "  end\nend\n",
    Mod = compile_and_load(Src),
    ?assert(Mod:run()).

e2e_password_wrong_test() ->
    Src = "module CryptoPwBad\n"
          "  def run()\n"
          "    hash = Crypto.hash_password(\"s3cret\")\n"
          "    Crypto.verify_password(\"wrong\", hash)\n"
          "  end\nend\n",
    Mod = compile_and_load(Src),
    ?assertNot(Mod:run()).
