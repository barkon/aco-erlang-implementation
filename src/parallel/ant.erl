-module (ant).
-export ([initAnts/5, ant/5, initTechnicalAnt/1, technicalAnt/1]).

% Pheromone level deposition constant; Pheromone deposited on a node = Q/Lk
% where Lk is a cost of the k'th ant tour, typically, in our case, lenght of the tour
-define(Q, 210).

% a parameter to control the influence of pheromones
-define(Alfa, 1).

% a parameter to control the influence the desirability of state transition
% typically 1 / dxy where d is the distance
-define(Beta, 1).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%                ANT                %%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% INITIALIZE ANTS
initAnts(_Master, _Iterations, _N, 0, _NodesPids) -> ok;
initAnts(TechnicalAnt, Iterations, N, AntsQuantity, NodesPids) -> 
	Ant = spawn(ant, ant, [TechnicalAnt, Iterations, NodesPids, 0, []]),
	Ant ! {init, {rand:uniform(N)}},
	initAnts(TechnicalAnt, Iterations, N, AntsQuantity - 1, NodesPids).

% UPDATE PHEROMONE LEVEL ON TRAVERSED PATH
updatePheromonesOnPath(_, _, [ _ | []]) -> ok;
updatePheromonesOnPath(NodesPids, Addition, [ First | [ Next | _ ] = Path ] ) ->
    FirstPid = maps:get(First, NodesPids),
    NextPid = maps:get(Next, NodesPids),
    FirstPid ! {update, {Next, Addition}},
    NextPid ! {update, {First, Addition}},
    updatePheromonesOnPath(NodesPids, Addition, Path).

% SUM VALUES IN A MAP
sumMap(Map) ->
    lists:sum(maps:values(Map)).

% COUNT PROBABILITY OF GIVEN EDGE
probabilityUnnormalized(Distance, Pheromone) ->
    math:pow(Pheromone, ?Alfa) * math:pow(1 / Distance, ?Beta).

% COUNT PROBABILITY MAP OF ALL PASSED NODES - EDGES
% ASSUMPTION: Keys of DistanceTo are equal to those of Pheromones map
countProbability(DistanceTo, Pheromones) -> 
    countProbability(maps:keys(DistanceTo), DistanceTo, Pheromones, #{}).
countProbability([], _, _, Acc) -> 
	Sum = sumMap(Acc),
	Normalize = fun(K, V, Axx) -> maps:put(K, V/Sum, Axx) end,
	NormalizedProbabilities = maps:fold(Normalize, #{}, Acc),
	NormalizedProbabilities;
countProbability([NodeNo | Nodes], DistanceTo, Pheromones, Acc) ->
    Distance = maps:get(NodeNo, DistanceTo),
    Pheromone = maps:get(NodeNo, Pheromones),
    Probability = probabilityUnnormalized(Distance, Pheromone),
	countProbability(Nodes, DistanceTo, Pheromones, maps:put(NodeNo, Probability, Acc)).
	
% ROULETTE WHEEL SELECTION METHOD
rouletteWheel(Probabilities, SumOf) -> 
	Nodes = maps:keys(Probabilities),
	[First | _] = Nodes,
	rouletteWheel(Probabilities, rand:uniform() * SumOf , Nodes, maps:get(First, Probabilities)).
rouletteWheel(_, _, [Last], _) -> Last;
rouletteWheel(Probabilities, Rand, [First | [Second | _] = ReducedNodes], Prob) ->
	case Prob < Rand of
		true -> 
			NewProb = Prob + maps:get(Second, Probabilities),
			rouletteWheel(Probabilities, Rand, ReducedNodes, NewProb);
		false ->
			First
	end.

% SELECT NEXT NODE BASED ON PROBABILITIES USING ROULETTE WHEEL SELECTION
selectNextNode(DistanceTo, Pheromones, Visited) ->
    DistanceToOfNTV = maps:without(Visited, DistanceTo),
    PheromonesOfNTV = maps:without(Visited, Pheromones),
    ProbabilitiesOfNTV = countProbability(DistanceToOfNTV, PheromonesOfNTV),
	SumOfProbabilities = sumMap(ProbabilitiesOfNTV),
	rouletteWheel(ProbabilitiesOfNTV, SumOfProbabilities).

% ANT PROCESS MESSAGE HANDLING
ant(TechnicalAnt, Iterations, NodesPids, Distance, Path) -> 
    receive
        {init, {StartNode}} -> 
			NodePid = maps:get(StartNode, NodesPids),
			NodePid ! {where, {self()}},
			ant(TechnicalAnt, Iterations, NodesPids, Distance, [ StartNode | Path]);
        {decide, {DistanceTo, Pheromones}} -> 
			case maps:size(NodesPids) == length(Path) of
				true ->
					FirstNode = lists:last(Path),
                    DistToFirst = maps:get(FirstNode, DistanceTo),
                    self() ! {finish},
					ant(TechnicalAnt, Iterations, NodesPids, Distance + DistToFirst, lists:reverse([ FirstNode | Path]));
				false ->
            		NextNode = selectNextNode(DistanceTo, Pheromones, Path),
                    NextNodePid = maps:get(NextNode, NodesPids),
                    NextNodePid ! {where, {self()}},
                    DistToNode = maps:get(NextNode, DistanceTo),
                    ant(TechnicalAnt, Iterations, NodesPids, Distance + DistToNode, [ NextNode | Path])
            end;
		{finish} -> 
            % send to master info of best fitness
			TechnicalAnt ! {check, {self(), Distance, Path}},
			% UNCOMMENT IF YOU WISH TO SEE EVERY SINGLE ANT'S DISTANCE AND PATH
			% io:format("\nAnt: Distance: ~w,\tPath: ~w", [Distance, Path]),
            % update pheromone table on path
            Addition = ?Q / Distance,
            updatePheromonesOnPath(NodesPids, Addition, Path),
            % restart ant's journey
            self() ! {init, {rand:uniform(maps:size(NodesPids))}},
            case Iterations of 
                0 -> 
                    TechnicalAnt ! {antdied},
                    exit(kill);
                _ -> ant(TechnicalAnt, Iterations - 1, NodesPids, 0, [])
            end;
		% {die} ->
        %     io:format("I die\n"),
		% 	exit(kill);
        _ ->
            ant(TechnicalAnt, Iterations, NodesPids, Distance, Path)
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%           TECHNICAL ANT           %%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% DISTRIBUTE GIVEN MESSAGE TO ALL NODES METHOD
distributeToNodes(NodesPids, Msg) -> distributeToNodes(NodesPids, Msg, maps:next(maps:iterator(NodesPids))).
distributeToNodes(_, _, none) -> ok;
distributeToNodes(NodesPids, Msg, {_, NodePid, NewIterator}) ->
    NodePid ! {Msg},
	distributeToNodes(NodesPids, Msg, maps:next(NewIterator)).

% INITIALIZE TECHNICAL ANT
initTechnicalAnt(NodesPids) -> 
    spawn(ant, technicalAnt, [NodesPids]).

% TECHNICAL ANT PROCESS MESSAGE HANDLING
technicalAnt(AntsQuantity, Iterations, NodesPids, Distance, Path) -> 
    receive
        {init, {StartNode}} -> 
            NodePid = maps:get(StartNode, NodesPids),
            NodePid ! {where, {self()}},
            ant(AntsQuantity, Iterations, NodesPids, Distance, [ StartNode | Path]);
        {decide, {DistanceTo, Pheromones}} -> 
            case maps:size(NodesPids) == length(Path) of
                true ->
                    FirstNode = lists:last(Path),
                    DistToFirst = maps:get(FirstNode, DistanceTo),
                    self() ! {finish},
                    ant(AntsQuantity, Iterations, NodesPids, Distance + DistToFirst, lists:reverse([ FirstNode | Path]));
                false ->
                    NextNode = selectNextNode(DistanceTo, Pheromones, Path),
                    NextNodePid = maps:get(NextNode, NodesPids),
                    NextNodePid ! {where, {self()}},
                    DistToNode = maps:get(NextNode, DistanceTo),
                    ant(AntsQuantity, Iterations, NodesPids, Distance + DistToNode, [ NextNode | Path])
            end;
        {finish} -> 
            % send to master info of best fitness
            AntsQuantity ! {check, {self(), Distance, Path}},
            % UNCOMMENT IF YOU WISH TO SEE EVERY SINGLE ANT'S DISTANCE AND PATH
            % io:format("\nAnt: Distance: ~w,\tPath: ~w", [Distance, Path]),
            % update pheromone table on path
            Addition = ?Q / Distance,
            updatePheromonesOnPath(NodesPids, Addition, Path),
            % restart ant's journey
            self() ! {init, {rand:uniform(maps:size(NodesPids))}},
            case Iterations of 
                0 -> io:format("I die\n"), exit(kill);
                _ -> ant(TechnicalAnt, Iterations - 1, NodesPids, 0, [])
            end;
        {killnodes} ->
            % kill all nodes and also technical ant exits (dies :c)
            distributeToNodes(NodesPids, die);
        _ ->
            ant(TechnicalAnt, Iterations, NodesPids, Distance, Path)
    end.