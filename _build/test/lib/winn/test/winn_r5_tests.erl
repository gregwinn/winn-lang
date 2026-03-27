%% winn_r5_tests.erl — R5: Crypto and hashing.

-module(winn_r5_tests).
-include_lib("eunit/include/eunit.hrl").

compile_and_load(Source) ->
    {ok, Tokens, _} = winn_lexer:string(Source),
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
