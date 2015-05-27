-module(spts_core_SUITE).
-author('elbrujohalcon@inaka.net').

-include_lib("mixer/include/mixer.hrl").
-mixin([
        {spts_test_utils,
         [ init_per_suite/1
         , end_per_suite/1
         ]}
       ]).

-export([ all/0
        , init_per_testcase/2
        , end_per_testcase/2
        ]).
-export([ game_creation_default/1
        , game_creation_with_options/1
        , game_creation_bad_rows/1
        , game_creation_bad_cols/1
        , game_creation_bad_ticktime/1
        , game_creation_bad_countdown/1
        , add_serpent_ok/1
        , add_serpent_wrong/1
        , too_many_serpents/1
        , start_game/1
        , turn_wrong/1
        , turn_ok/1
        ]).

-spec all() -> [atom()].
all() -> spts_test_utils:all(?MODULE).

-spec init_per_testcase(atom(), spts_test_utils:config()) ->
  spts_test_utils:config().
init_per_testcase(turn_ok, Config0) ->
  Config = init_per_testcase(turn_wrong, Config0),
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),
  spts_core:add_serpent(GameId, <<"serp1">>),
  spts_core:add_serpent(GameId, <<"serp2">>),
  Config;
init_per_testcase(AddSerpentTest, Config)
  when AddSerpentTest == add_serpent_ok
     ; AddSerpentTest == add_serpent_wrong
     ; AddSerpentTest == start_game
     ; AddSerpentTest == turn_wrong ->
  Game = spts_core:create_game(#{cols => 10, rows => 10, countdown => 2}),
  [{game, Game} | Config];
init_per_testcase(_Test, Config) -> Config.

-spec end_per_testcase(atom(), spts_test_utils:config()) ->
  spts_test_utils:config().
end_per_testcase(AddSerpentTest, Config)
  when AddSerpentTest == add_serpent_ok
     ; AddSerpentTest == add_serpent_wrong
     ; AddSerpentTest == start_game
     ; AddSerpentTest == turn_wrong ->
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),
  ok = spts_core:stop_game(GameId),
  lists:keydelete(game, 1, Config);
end_per_testcase(_Test, Config) -> Config.

-spec game_creation_default(spts_test_utils:config()) ->
  {comment, string()}.
game_creation_default(_Config) ->
  ct:comment("Create a game with default options"),
  Game = spts_core:create_game(),
  20 = spts_games:rows(Game),
  20 = spts_games:cols(Game),
  250 = spts_games:ticktime(Game),
  10 = spts_games:countdown(Game),
  created = spts_games:state(Game),
  [] = spts_games:serpents(Game),
  {comment, ""}.

-spec game_creation_with_options(spts_test_utils:config()) ->
  {comment, string()}.
game_creation_with_options(_Config) ->
  ct:comment("Create a game with more rows"),
  Game0 = spts_core:create_game(#{rows => 40}),
  40 = spts_games:rows(Game0),
  20 = spts_games:cols(Game0),
  250 = spts_games:ticktime(Game0),
  10 = spts_games:countdown(Game0),

  ct:comment("Create a game with more cols"),
  Game1 = spts_core:create_game(#{cols => 30}),
  20 = spts_games:rows(Game1),
  30 = spts_games:cols(Game1),
  250 = spts_games:ticktime(Game1),
  10 = spts_games:countdown(Game1),

  ct:comment("Create a game with more ticktime"),
  Game2 = spts_core:create_game(#{ticktime => 300}),
  20 = spts_games:rows(Game2),
  20 = spts_games:cols(Game2),
  300 = spts_games:ticktime(Game2),
  10 = spts_games:countdown(Game2),

  ct:comment("Create a game with less cols and rows"),
  Game3 = spts_core:create_game(#{cols => 10, rows => 10}),
  10 = spts_games:rows(Game3),
  10 = spts_games:cols(Game3),
  250 = spts_games:ticktime(Game3),
  10 = spts_games:countdown(Game3),

  Game4 = spts_core:create_game(#{countdown => 25}),
  20 = spts_games:rows(Game4),
  20 = spts_games:cols(Game4),
  250 = spts_games:ticktime(Game4),
  25 = spts_games:countdown(Game4),

  Game5 = spts_core:create_game(#{ticktime => 400, countdown => 25}),
  20 = spts_games:rows(Game5),
  20 = spts_games:cols(Game5),
  400 = spts_games:ticktime(Game5),
  25 = spts_games:countdown(Game5),

  ct:comment("Create a game with less cols, rows and ticktime"),
  GameF =
    spts_core:create_game(
      #{cols => 10, rows => 10, ticktime => 500, countdown => 0}),
  10 = spts_games:rows(GameF),
  10 = spts_games:cols(GameF),
  500 = spts_games:ticktime(GameF),
  0 = spts_games:countdown(GameF),

  {comment, ""}.

-spec game_creation_bad_rows(spts_test_utils:config()) ->
  {comment, string()}.
game_creation_bad_rows(_Config) ->
  TryWith =
    fun(R) ->
      try spts_core:create_game(#{rows => R}) of
        G -> ct:fail("Unexpected game with ~p rows: ~p", [R, G])
      catch
        throw:invalid_rows -> ok
      end
    end,

  ct:comment("Negative rows fails"),
  TryWith(-10),

  ct:comment("0 rows fails"),
  TryWith(0),

  ct:comment("Less than 5 rows fails"),
  TryWith(4),

  {comment, ""}.

-spec game_creation_bad_cols(spts_test_utils:config()) -> {comment, string()}.
game_creation_bad_cols(_Config) ->
  TryWith =
    fun(R) ->
      try spts_core:create_game(#{cols => R}) of
        G -> ct:fail("Unexpected game with ~p cols: ~p", [R, G])
      catch
        throw:invalid_cols -> ok
      end
    end,

  ct:comment("Negative cols fails"),
  TryWith(-10),

  ct:comment("0 cols fails"),
  TryWith(0),

  ct:comment("Less than 5 cols fails"),
  TryWith(4),

  {comment, ""}.

-spec game_creation_bad_ticktime(spts_test_utils:config()) ->
  {comment, string()}.
game_creation_bad_ticktime(_Config) ->
  TryWith =
    fun(T) ->
      try spts_core:create_game(#{ticktime => T}) of
        G -> ct:fail("Unexpected game with ticktime == ~p: ~p", [T, G])
      catch
        throw:invalid_ticktime -> ok
      end
    end,

  ct:comment("Negative ticktime fails"),
  TryWith(-10),

  ct:comment("0 ticktime fails"),
  TryWith(0),

  ct:comment("Less than 100 ticktime fails"),
  TryWith(4),

  {comment, ""}.

-spec game_creation_bad_countdown(spts_test_utils:config()) ->
  {comment, string()}.
game_creation_bad_countdown(_Config) ->
  ct:comment("Negative countdown fails"),
  try spts_core:create_game(#{countdown => -15}) of
    G -> ct:fail("Unexpected game with negative countdown: ~p", [G])
  catch
    throw:invalid_countdown -> ok
  end,

  {comment, ""}.

-spec add_serpent_ok(spts_test_utils:config()) -> {comment, string()}.
add_serpent_ok(Config) ->
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),

  ct:comment("There is noone on the game"),
  [] = spts_games:serpents(spts_core:fetch_game(GameId)),

  ct:comment("serp1 is aded"),
  Serpent1 = spts_core:add_serpent(GameId, <<"serp1">>),
  [{Row1, Col1}] = spts_serpents:body(Serpent1),
  true =
    lists:member(spts_serpents:direction(Serpent1), [up, down, left, right]),
  true = Row1 > 0,
  true = Row1 < 11,
  true = Col1 > 0,
  true = Col1 < 11,
  [Serpent1] = spts_games:serpents(spts_core:fetch_game(GameId)),
  <<"serp1">> = spts_serpents:name(Serpent1),

  ct:comment("serp2 is added"),
  Serpent2 = spts_core:add_serpent(GameId, <<"serp2">>),
  [{Row2, Col2}] = spts_serpents:body(Serpent2),
  true =
    lists:member(spts_serpents:direction(Serpent2), [up, down, left, right]),
  true = Row2 > 0,
  true = Row2 < 11,
  true = Col2 > 0,
  true = Col2 < 11,
  [Serpent2] = spts_games:serpents(spts_core:fetch_game(GameId)) -- [Serpent1],
  <<"serp2">> = spts_serpents:name(Serpent2),

  ct:comment("serp3 is added"),
  Serpent3 = spts_core:add_serpent(GameId, <<"serp3">>),
  [{Row3, Col3}] = spts_serpents:body(Serpent3),
  true =
    lists:member(spts_serpents:direction(Serpent3), [up, down, left, right]),
  true = Row3 > 0,
  true = Row3 < 11,
  true = Col3 > 0,
  true = Col3 < 11,
  [Serpent3] =
    spts_games:serpents(spts_core:fetch_game(GameId)) --
      [Serpent1, Serpent2],
  <<"serp3">> = spts_serpents:name(Serpent3),

  {comment, ""}.

-spec add_serpent_wrong(spts_test_utils:config()) -> {comment, string()}.
add_serpent_wrong(Config) ->
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),

  ct:comment("There is noone on the game"),
  [] = spts_games:serpents(spts_core:fetch_game(GameId)),

  ct:comment("serp1 is added"),
  spts_core:add_serpent(GameId, <<"serp1">>),
  [Serpent1] = spts_games:serpents(spts_core:fetch_game(GameId)),
  <<"serp1">> = spts_serpents:name(Serpent1),

  ct:comment("serp1 tries to be added to the game again"),
  try spts_core:add_serpent(GameId, <<"serp1">>) of
    R2 -> ct:fail("Duplicated serpent ~p in ~p (~p)", [<<"serp1">>, GameId, R2])
  catch
    throw:already_in -> ok
  end,
  [Serpent1] = spts_games:serpents(spts_core:fetch_game(GameId)),

  ct:comment("serp2 can't be added while on countdown"),
  ok = spts_core:start_game(GameId),
  ktn_task:wait_for(
    fun() ->
      spts_games:state(spts_core:fetch_game(GameId))
    end, countdown),
  try spts_core:add_serpent(GameId, <<"serp2">>) of
    R4 -> ct:fail("Unexpected serpent in ~p: ~p", [GameId, R4])
  catch
    throw:invalid_state -> ok
  end,
  [Serpent1] = spts_games:serpents(spts_core:fetch_game(GameId)),

  ct:comment("serp2 can't be added after game starts"),
  ktn_task:wait_for(
    fun() ->
      spts_games:state(spts_core:fetch_game(GameId))
    end, started),
  try spts_core:add_serpent(GameId, <<"serp2">>) of
    R5 -> ct:fail("Unexpected serpent in ~p: ~p", [GameId, R5])
  catch
    throw:invalid_state -> ok
  end,
  [Serpent1] = spts_games:serpents(spts_core:fetch_game(GameId)),

  {comment, ""}.

-spec too_many_serpents(spts_test_utils:config()) -> {comment, string()}.
too_many_serpents(_Config) ->
  ct:comment("A small game is created"),
  Game = spts_core:create_game(#{cols => 5, rows => 5}),
  GameId = spts_games:id(Game),

  ct:comment("Enough serpents to fill the whole board are created"),
  Chars = lists:seq($a, $a + 24),
  Serpents = [<<"serp-", C>> || C <- Chars],

  ct:comment("They all try to be added the game, at least one must fail"),
  AddResults =
    lists:map(
      fun(SerpentName) ->
        try spts_core:add_serpent(GameId, SerpentName)
        catch
          throw:game_full -> game_full
        end
      end, Serpents),

  {[_|_], SerpentsInGame} =
    lists:partition(fun(X) -> X == game_full end, AddResults),

  ct:comment("All serpents should be free to move"),
  NewGame = spts_core:fetch_game(GameId),
  lists:foreach(
    fun(Serpent) ->
      [Position] = spts_serpents:body(Serpent),
      Direction = spts_serpents:direction(Serpent),
      NewPosition = spts_test_utils:move(Position, Direction),
      true = spts_games:is_empty(NewGame, NewPosition),
      in = spts_test_utils:check_bounds(NewGame, NewPosition)
    end, SerpentsInGame),

  {comment, ""}.

-spec start_game(spts_test_utils:config()) -> {comment, string()}.
start_game(Config) ->
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),

  ct:comment("The game can't start if there is noone in it"),
  [] = spts_games:serpents(spts_core:fetch_game(GameId)),
  ok = spts_core:start_game(GameId),
  created = spts_games:state(spts_core:fetch_game(GameId)),

  ct:comment("The game can start after the first serpent is added"),
  spts_core:add_serpent(GameId, <<"serp1">>),
  ok = spts_core:start_game(GameId),
  countdown = spts_games:state(spts_core:fetch_game(GameId)),

  ct:comment("Trying to start the game again has no effect"),
  ok = spts_core:start_game(GameId),
  countdown = spts_games:state(spts_core:fetch_game(GameId)),

  ct:comment("We wait for the game to actually start"),
  ktn_task:wait_for(
    fun() ->
      spts_games:state(spts_core:fetch_game(GameId))
    end, started),

  ct:comment("Trying to start the game again has no effect"),
  ok = spts_core:start_game(GameId),
  started = spts_games:state(spts_core:fetch_game(GameId)),

  {comment, ""}.

-spec turn_wrong(spts_test_utils:config()) -> {comment, string()}.
turn_wrong(Config) ->
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),

  ct:comment("Turn is inconsequential if the serpent isn't playing"),
  [] = spts_games:serpents(spts_core:fetch_game(GameId)),
  ok = spts_core:turn(GameId, <<"serp1">>, right),
  [] = spts_games:serpents(spts_core:fetch_game(GameId)),

  ct:comment("A serpent that's outside the game can't turn"),
  Serpent = spts_core:add_serpent(GameId, <<"serp1">>),
  D1 = spts_serpents:direction(Serpent),
  ok = spts_core:turn(GameId, <<"serp2">>, right),
  D1 =
    spts_serpents:direction(
      spts_games:serpent(
        spts_core:fetch_game(GameId), <<"serp1">>)),

  {comment, ""}.

-spec turn_ok(spts_test_utils:config()) -> {comment, string()}.
turn_ok(Config) ->
  {game, Game} = lists:keyfind(game, 1, Config),
  GameId = spts_games:id(Game),

  TryWith =
    fun(SerpentName, Direction) ->
      spts_core:turn(GameId, SerpentName, Direction),
      { spts_serpents:direction(
          spts_games:serpent(
            spts_core:fetch_game(GameId), <<"serp1">>))
      , spts_serpents:direction(
          spts_games:serpent(
            spts_core:fetch_game(GameId), <<"serp2">>))
      }
    end,

  FullRound =
    fun() ->
      {up, _} = TryWith(<<"serp1">>, up),
      {up, up} = TryWith(<<"serp2">>, up),
      {down, up} = TryWith(<<"serp1">>, down),
      {down, down} = TryWith(<<"serp2">>, down),
      {down, left} = TryWith(<<"serp2">>, left),
      {left, left} = TryWith(<<"serp1">>, left),
      {left, right} = TryWith(<<"serp2">>, right),
      {right, right} = TryWith(<<"serp1">>, right)
    end,

  ct:comment("Before the game starts, serpents can turn"),
  FullRound(),

  ct:comment("After the game starts, serpents can turn"),
  spts_core:start_game(GameId),
  FullRound(),

  {comment, ""}.