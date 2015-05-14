%% @doc Games model
-module(serpents_games).
-author('elbrujohalcon@inaka.net').

-type content() :: air
                 | wall
                 | fruit
                 | {serpent, head | body, serpents_players:id()}.
-type cell() ::
  #{ position => serpents_core:position()
   , content => content()
   }.
-type state() :: created | started | finished.
-opaque id() :: binary().
-opaque game() ::
  #{
    id => binary(),
    players => [serpents_players:id()],
    state => state(),
    rows => pos_integer(),
    cols => pos_integer(),
    cells => [cell()],
    process => undefined | pid(),
    created_at => dcn_datetime:datetime(),
    updated_at => dcn_datetime:datetime()
  }.
-export_type([game/0, state/0, id/0, content/0]).

-export(
  [ new/2
  , id/1
  , rows/1
  , cols/1
  , state/1
  , players/1
  , process/2
  , head/2
  , content/2
  , add_player/3
  ]).

-spec new(pos_integer(), pos_integer()) -> game().
new(Rows, _Cols) when Rows < 5 -> throw(invalid_rows);
new(_Rows, Cols) when Cols < 5 -> throw(invalid_cols);
new(Rows, Cols) ->
  Now = ktn_date:now_human_readable(),
  #{ id => uuid:uuid_to_string(uuid:get_v4(), binary_standard)
   , players => []
   , state => created
   , rows => Rows
   , cols => Cols
   , cells => []
   , process => undefined
   , created_at => Now
   , updated_at => Now
   }.

-spec id(game()) -> id().
id(#{id := Id}) -> Id.

-spec rows(game()) -> pos_integer().
rows(#{rows := Rows}) -> Rows.

-spec cols(game()) -> pos_integer().
cols(#{cols := Cols}) -> Cols.

-spec state(game()) -> state().
state(#{state := State}) -> State.

-spec players(game()) -> [serpents_players:id()].
players(#{players := Players}) -> Players.

-spec process(game(), pid()) -> game().
process(Game, Process) -> Game#{process => Process}.

%% @doc where is the head of this player's serpent
-spec head(game(), serpents_players:id()) ->
  serpents_core:position() | notfound.
head(#{cells := Cells}, PlayerId) ->
  Heads =
    [ Position
    || #{position := Position, content := {serpent, head, P}} <- Cells
     , P == PlayerId],
  case Heads of
    [] -> notfound;
    [H|_] -> H
  end.

%% @doc returns the content of the cell at that position
-spec content(game(), serpents_core:position()) -> content().
content(#{cells := Cells}, Position) ->
  case [Cell || Cell = #{position := P} <- Cells, P == Position] of
    [] -> air;
    [#{content := Content}] -> Content
  end.

%% @doc adds a new player to the game
-spec add_player(game(), serpents_players:id(), serpents_core:position()) ->
  game().
add_player(Game, PlayerId, Position) ->
  #{ players := Players
   , cells := Cells
   } = Game,
  Cell = #{position => Position, content => {serpent, head, PlayerId}},
  Game#{players := [PlayerId | Players], cells := [Cell |Cells]}.
