%%%----------------------------------------------------------------------
%%% File    : ejabberd_auth_jwt.erl
%%% Author  : Rogerio da Silva Yokomizo <me@ro.ger.io>
%%% Purpose : Authentification via JWT token
%%% Created : 10 May 2018 by Rogerio da Silva Yokomizo <me@ro.ger.io>
%%%
%%%
%%% Copyright 2018 Rogerio da Silva Yokomizo
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%----------------------------------------------------------------------

-module(ejabberd_auth_jwt).

-behaviour(gen_mod).

-author('me@ro.ger.io').

-export([check_password/4, depends/2, mod_options/1, mod_opt_type/1,
	 plain_password_required/1, reload/1, remove_user/2,
	 set_password/3, start/1, start/2, stop/1, store_type/1,
	 try_register/3, use_cache/1, user_exists/2]).

-record(jose_jwt, {fields = #{}  :: map()}).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%%%----------------------------------------------------------------------
%%% API
%%%----------------------------------------------------------------------
start(_Host) -> ok.

start(_Host, _Opts) -> ok.

stop(_Host) -> ok.

reload(_Host) -> ok.

plain_password_required(_) -> true.

use_cache(_) -> false.

store_type(_) -> external.

check_password(User, AuthzId, Server, Password) ->
    if AuthzId /= <<>> andalso AuthzId /= User -> false;
       true -> check_password_jwt(User, Server, Password)
    end.

set_password(_User, _Server, _Password) ->
    {error, not_allowed}.

try_register(_User, _Server, _Password) ->
    {error, not_allowed}.

user_exists(_User, _Server) -> true.

remove_user(_User, _Server) -> {error, not_allowed}.

depends(_Host, _Opts) -> [].

mod_opt_type(strict_alg) -> fun iolist_to_binary/1;
mod_opt_type(user_claim) -> fun iolist_to_binary/1;
mod_opt_type(key) -> fun iolist_to_binary/1;
mod_opt_type(pem_file) -> fun iolist_to_binary/1;
mod_opt_type(_) ->
    [key, pem_file, user_claim, strict_alg].

mod_options(_) ->
    [{key, []},{pem_file, []}, {user_claim, []},{strict_alg, []}].


%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------
check_password_jwt(User, Server, Fields)
    when is_map(Fields) ->
    UserClaim =
        gen_mod:get_module_opt(Server, ?MODULE, user_claim),
    case maps:find(UserClaim, Fields) of
      {ok, User} -> true;
      _ -> false
    end;
check_password_jwt(User, Server, Password) ->
    JWK = get_jwk(Server),
    Alg = gen_mod:get_module_opt(Server, ?MODULE, strict_alg),
    try verify_token(JWK, Alg, Password) of
      {true, #jose_jwt{fields = Fields}, _} ->
	  check_password_jwt(User, Server, Fields);
      _ ->
          false
    catch
      _:_ -> false
    end.

verify_token(JWK, <<"">>, Token) ->
    jose_jwt:verify(JWK, Token);
verify_token(JWK, Alg, Token) ->
    jose_jwt:verify_strict(JWK, [Alg], Token).

get_jwk(Server) ->
    case gen_mod:get_module_opt(Server, ?MODULE, pem_file)
	of
      <<"">> ->
          HS256Key = gen_mod:get_module_opt(Server, ?MODULE, key),
          HS256KeyBase64 = base64url:encode(HS256Key),
	  #{<<"kty">> => <<"oct">>, <<"k">> => HS256KeyBase64};
      RSAKeyFile ->
          jose_jwk:from_pem_file(RSAKeyFile)
    end.

%%%----------------------------------------------------------------------
%%% Tests
%%%----------------------------------------------------------------------
-ifdef(TEST).
start_test() ->
    ?assertEqual(ok, start("")),
    ?assertEqual(ok, start("", "")).

stop_test() ->
    ?assertEqual(ok, stop("")).

reload_test() ->
    ?assertEqual(ok, reload("")).

plain_password_required_test() ->
    ?assert(plain_password_required("")).

use_cache_test() ->
    ?assertEqual(false, use_cache("")).

store_type_test() ->
    ?assertEqual(external, store_type("")).

verify_token_test() ->
    jose:json_module(jiffy), 
    JWK = #{<<"kty">> => <<"oct">>, <<"k">> => <<"U0VDUkVU">>},
    ValidToken = <<"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ._XEngvIuxOcA-j7y_upRUbXli4DLToNf7HxH1XNmxSc">>,
    { true, _, _ } = verify_token(JWK, <<"">>, ValidToken),
    { true, _, _ } = verify_token(JWK, <<"HS256">>, ValidToken),
    { false, _, _ } = verify_token(JWK, <<"RS256">>, ValidToken).
-endif.

