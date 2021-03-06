%%% @doc The core of the game
-module(spts_core).
-author('elbrujohalcon@inaka.net').

-behavior(gen_fsm).

-type game_id() :: spts_games:id() | pos_integer().

-record(state, {game :: spts_games:game(), dispatcher :: pid()}).

-type state() :: #state{}.

-export(
  [ create_game/0
  , create_game/1
  , add_serpent/2
  , start_game/1
  , stop_game/1
  , turn/3
  , is_game/1
  , fetch_game/1
  , can_start/1
  , all_games/0
  , subscribe/3
  , call_handler/3
  ]).

-export([start_link/1]).
-export(
  [ created/3
  , created/2
  , open/3
  , open/2
  , closed/3
  , closed/2
  , countdown/3
  , countdown/2
  , started/3
  , started/2
  , finished/3
  , finished/2
  , init/1
  , handle_event/3
  , handle_sync_event/4
  , handle_info/3
  , terminate/3
  , code_change/4
  ]).

-type options() :: #{ rows => pos_integer()
                    , cols => pos_integer()
                    , ticktime => Milliseconds :: pos_integer()
                    , countdown => CountdownRounds :: non_neg_integer()
                    , rounds => GameRounds :: pos_integer()
                    , initial_food => non_neg_integer()
                    , max_serpents => pos_integer()
                    , flags => [spts_games:flag()]
                    }.
-export_type([options/0]).

-type event() ::
    {serpent_added, spts_serpents:serpent()}
  | {game_countdown, spts_games:game()}
  | {game_started, spts_games:game()}
  | {game_updated, spts_games:game()}
  | {collision_detected, spts_serpents:serpent()}
  | {game_finished, spts_games:game()}.
-export_type([event/0]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% EXPORTED FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% @equiv create_game(#{}).
-spec create_game() -> spts_games:game().
create_game() -> create_game(#{}).

%% @doc Creates a new game
-spec create_game(options()) -> spts_games:game().
create_game(Options) ->
  Game = spts_games_repo:create(Options),
  {ok, _Pid} = spts_game_sup:start_child(Game),
  Game.

%% @doc Adds a serpent to GameId
-spec add_serpent(game_id(), spts_serpents:name()) ->
  spts_serpents:serpent().
add_serpent(GameId, SerpentName) ->
  call(GameId, {add_serpent, SerpentName}).

%% @doc Can we start the game?
-spec can_start(game_id()) -> boolean().
can_start(GameId) ->
  call(GameId, can_start).

%% @doc Closes the joining period for the game and starts it
-spec start_game(game_id()) -> ok.
start_game(GameId) ->
  cast(GameId, start).

%% @doc Stops the game
-spec stop_game(game_id()) -> ok.
stop_game(GameId) ->
  cast(GameId, stop).

%% @doc a serpent changes direction
-spec turn(game_id(), spts_serpents:name(), spts_games:direction()) -> ok.
turn(GameId, SerpentName, Direction) ->
  cast(GameId, {turn, SerpentName, Direction}).

%% @doc Retrieves the status of a game
-spec fetch_game(game_id()) ->
  spts_games:game().
fetch_game(GameId) ->
  call(GameId, fetch).

%% @doc Is this game running?
-spec is_game(game_id()) -> boolean().
is_game(GameId) ->
  undefined =/= erlang:whereis(spts_games:process_name(GameId)).

%% @doc Retrieves the list of all currently held games
-spec all_games() -> [spts_games:game()].
all_games() ->
  Children = supervisor:which_children(spts_game_sup),
  Processes = [Pid || {undefined, Pid, worker, [?MODULE]} <- Children],
  lists:map(
    fun(Process) ->
      {ok, Result} = do_call(Process, fetch),
      Result
    end, Processes).

%% @doc Subscribes to the game gen_event dispatcher using gen_event:swap_handler
-spec subscribe(game_id(), module() | {module(), term()}, term()) ->
  ok.
subscribe(GameId, Handler, Args) ->
  gen_event:swap_handler(
    call(GameId, dispatcher), {Handler, Args}, {Handler, Args}).

%% @doc Calls the game gen_event dispatcher.
-spec call_handler(game_id(), module() | {module(), term()}, term()) ->
  term().
call_handler(GameId, Handler, Request) ->
  gen_event:call(call(GameId, dispatcher), Handler, Request).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% PRIVATELY EXPORTED FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec start_link(spts_games:game()) -> {ok, pid()} | {error, term()}.
start_link(Game) ->
  Process = spts_games:process_name(spts_games:id(Game)),
  gen_fsm:start_link({local, Process}, ?MODULE, Game, []).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% FSM CALLBACKS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
-spec init(spts_games:game()) -> {ok, created, state()}.
init(Game) ->
  {ok, Dispatcher} = gen_event:start_link(),
  sys:trace(Dispatcher, true),
  {ok, created, #state{game = Game, dispatcher = Dispatcher}}.

-spec handle_event(stop, atom(), state()) -> {stop, normal, state()}.
handle_event(stop, _StateName, State) -> {stop, normal, State}.

-spec handle_sync_event
  (can_start, _From, atom(), state()) ->
    {reply, {ok, boolean()}, atom(), state()};
  (fetch, _From, atom(), state()) ->
    {reply, {ok, spts_games:game()}, atom(), state()};
  (dispatcher, _From, atom(), state()) ->
    {reply, {ok, pid()}, atom(), state()}.
handle_sync_event(can_start, _From, StateName, State) ->
  {reply, {ok, StateName =/= created}, StateName, State};
handle_sync_event(fetch, _From, StateName, State) ->
  {reply, {ok, State#state.game}, StateName, State};
handle_sync_event(dispatcher, _From, StateName, State) ->
  {reply, {ok, State#state.dispatcher}, StateName, State}.

-spec handle_info(tick|term(), atom(), state()) ->
  {next_state, atom(), state()}.
handle_info(tick, countdown, State) ->
  #state{game = Game} = State,
  NewGame = spts_games_repo:countdown_or_start(Game),
  case spts_games:state(NewGame) of
    started ->
      ok = notify({game_started, NewGame}, State),
      tick(Game),
      {next_state, started, State#state{game = NewGame}};
    countdown ->
      ok = notify({game_countdown, NewGame}, State),
      tick(NewGame),
      {next_state, countdown, State#state{game = NewGame}}
  end;
handle_info(tick, started, State) ->
  #state{game = Game} = State,
  NewGame = spts_games_repo:advance(Game),
  NewState = State#state{game = NewGame},
  OldDeadSerpents = dead_serpents(Game),
  NewDeadSerpents = dead_serpents(NewGame),
  lists:foreach(
    fun(DeadSerpent) ->
      notify({collision_detected, DeadSerpent}, NewState)
    end, NewDeadSerpents -- OldDeadSerpents),
  case spts_games:state(NewGame) of
    finished ->
      notify({game_finished, NewGame}, NewState),
      {next_state, finished, NewState};
    started ->
      notify({game_updated, NewGame}, NewState),
      tick(NewGame),
      {next_state, started, NewState}
  end;
handle_info(Info, StateName, State) ->
  _ = lager:notice("~p received at ~p", [Info, StateName]),
  {next_state, StateName, State}.

-spec terminate(term(), atom(), state()) -> ok.
terminate(Reason, StateName, State) ->
  catch gen_event:stop(State#state.dispatcher),
  _ = lager:notice("Terminating in ~p with reason ~p", [StateName, Reason]).

-spec code_change(term() | {down, term()}, atom(), state(), term()) ->
    {ok, atom(), state()}.
code_change(_, StateName, State, _) -> {ok, StateName, State}.

-spec created({add_serpent, spts_serpents:name()}, _From, state()) ->
  {reply, {ok, spts_serpents:serpent()} | {error, term()},
   open | closed, state()}.
created({add_serpent, SerpentName}, From, State) ->
  open({add_serpent, SerpentName}, From, State).

-spec created(term(), state()) -> {next_state, created, state()}.
created(Request, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {next_state, created, State}.

-spec open(
  {add_serpent, spts_serpents:name()}, _From, state()) ->
    {reply, {ok, spts_serpents:serpent()} | {error, term()},
     open | closed, state()}.
open({add_serpent, SerpentName}, _From, State) ->
  #state{game = Game} = State,
  try spts_games_repo:add_serpent(Game, SerpentName) of
    NewGame ->
      Serpent = spts_games:serpent(NewGame, SerpentName),
      ok = notify({serpent_added, Serpent}, State),
      NextState =
        case spts_games_repo:can_add_serpent(NewGame) of
          false -> closed;
          true -> open
        end,
      {reply, {ok, Serpent}, NextState, State#state{game = NewGame}}
  catch
    _:game_full ->
      {reply, {error, game_full}, closed, State};
    _:Error ->
      {reply, {error, Error}, open, State}
  end.

-spec open(
  {turn, spts_serpents:name(), spts_games:direction()} | start, state()) ->
  {next_state, started | open, state()}.
open({turn, SerpentName, Direction}, State) ->
  #state{game = Game} = State,
  try spts_games_repo:turn(Game, SerpentName, Direction) of
    NewGame ->
      {next_state, open, State#state{game = NewGame}}
  catch
    throw:invalid_serpent ->
      _ = lager:warning("Invalid Turn: ~p / ~p", [SerpentName, Direction]),
      {next_state, open, State}
  end;
open(start, State) ->
  handle_info(tick, countdown, State).

-spec closed(term(), _From, state()) ->
    {reply, {error, invalid_state}, closed, state()}.
closed(Request, _From, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {reply, {error, invalid_state}, closed, State}.

-spec closed(
  {turn, spts_serpents:name(), spts_games:direction()} | start,
  state()) -> {next_state, started | closed, state()}.
closed({turn, SerpentName, Direction}, State) ->
  #state{game = Game} = State,
  try spts_games_repo:turn(Game, SerpentName, Direction) of
    NewGame ->
      {next_state, closed, State#state{game = NewGame}}
  catch
    throw:invalid_serpent ->
      _ = lager:warning("Invalid Turn: ~p / ~p", [SerpentName, Direction]),
      {next_state, closed, State}
  end;
closed(start, State) ->
  handle_info(tick, countdown, State).

-spec countdown(term(), _From, state()) ->
    {reply, {error, invalid_state}, countdown, state()}.
countdown(Request, _From, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {reply, {error, invalid_state}, countdown, State}.

-spec countdown(
  {turn, spts_serpents:name(), spts_games:direction()} | term(),
  state()) -> {next_state, countdown, state()}.
countdown({turn, SerpentName, Direction}, State) ->
  #state{game = Game} = State,
  try spts_games_repo:turn(Game, SerpentName, Direction) of
    NewGame ->
      {next_state, countdown, State#state{game = NewGame}}
  catch
    throw:invalid_serpent ->
      _ = lager:warning("Invalid Turn: ~p / ~p", [SerpentName, Direction]),
      {next_state, countdown, State}
  end;
countdown(Request, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {next_state, countdown, State}.

-spec started(term(), _From, state()) ->
                {reply, {error, invalid_state}, started, state()}.
started(Request, _From, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {reply, {error, invalid_state}, started, State}.

-spec started(
  {turn, spts_serpents:name(), spts_games:direction()} | term(),
  state()) -> {next_state, started | finished, state()}.
started({turn, SerpentName, Direction}, State) ->
  #state{game = Game} = State,
  try spts_games_repo:turn(Game, SerpentName, Direction) of
    NewGame ->
      {next_state, started, State#state{game = NewGame}}
  catch
    throw:invalid_serpent ->
      _ = lager:warning("Invalid Turn: ~p / ~p", [SerpentName, Direction]),
      {next_state, started, State}
  end;
started(Request, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {next_state, started, State}.

-spec finished(term(), _From, state()) ->
                {reply, {error, invalid_state}, finished, state()}.
finished(Request, _From, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {reply, {error, invalid_state}, finished, State}.

-spec finished(term(), state()) -> {next_state, finished, state()}.
finished(Request, State) ->
  _ = lager:warning("Invalid Request: ~p", [Request]),
  {next_state, finished, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% INTERNAL FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
call(GameId, Event) when is_integer(GameId) ->
  Children = supervisor:which_children(spts_game_sup),
  Processes = [Pid || {undefined, Pid, worker, [?MODULE]} <- Children],
  NotGameId =
    fun(Process) ->
      {ok, Game} = do_call(Process, fetch),
      spts_games:numeric_id(Game) =/= GameId
    end,
  case lists:dropwhile(NotGameId, Processes) of
    [] ->
      _ = lager:error(
        "Couldn't send ~p to ~p: not a game~nStack: ~p",
        [Event, GameId, erlang:get_stacktrace()]),
      throw({badgame, GameId});
    [Process|_] ->
      try_call(Process, Event)
  end;
call(GameId, Event) ->
  Process = spts_games:process_name(GameId),
  try_call(Process, Event).

try_call(Process, Event) ->
  try do_call(Process, Event) of
    {ok, Result} -> Result;
    {error, Error} -> throw(Error)
  catch
    _:{noproc, _} ->
      _ = lager:error(
        "Couldn't send ~p to ~p: not a game~nStack: ~p",
        [Event, Process, erlang:get_stacktrace()]),
      throw({badgame, Process})
  end.

do_call(Process, can_start) ->
  gen_fsm:sync_send_all_state_event(Process, can_start);
do_call(Process, fetch) ->
  gen_fsm:sync_send_all_state_event(Process, fetch);
do_call(Process, dispatcher) ->
  gen_fsm:sync_send_all_state_event(Process, dispatcher);
do_call(Process, Event) ->
  gen_fsm:sync_send_event(Process, Event).

cast(GameId, stop) ->
  gen_fsm:send_all_state_event(spts_games:process_name(GameId), stop);
cast(GameId, Event) ->
  gen_fsm:send_event(spts_games:process_name(GameId), Event).

tick(Game) -> erlang:send_after(spts_games:ticktime(Game), self(), tick).

notify(Event, State) ->
  ok = gen_event:notify(State#state.dispatcher, Event).

dead_serpents(Game) ->
  [S || S <- spts_games:serpents(Game), spts_serpents:status(S) == dead].
