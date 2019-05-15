function [sol_found,W,handle_ConformalArray,PRx,I,bestScores] = CBG_solveit(problem,conf,candSet)
% CBG_solveit - Main PHY script that finds the optimal solution for HELB
% (see submited paper for further description), given the mmWave sub-array
% restrictions, the number of users, their channels and the demanded SNR
% per application.
%
% Syntax:  [sol_found,W,handle_ConformalArray,PRx,I,bestScores] = ...
%                               CBG_solveit(problem,conf,candSet)
%
% Inputs:
%    problem - struct containint configuration in data/metaproblem_test.dat
%    conf - struct containint configuration in data/config_test.dat
%    candSet - Vector containing the users IDs
%
% Outputs:
%    sol_found - flag indicating whether the solution was found
%    W - beamforming weights
%    handle_ConformalArray - handle with antenna locations in space
%    PRx - Vector with Generated Received power at intended users
%    I - Matrix with generated interference to non-intended users
%    bestScores - Vector containing the best solutions per iteration
%
% Other m-files required: CBG_creationArrayGA , CBG_CA_Position_Objective_optim_ga, ...
%                         CBG_geneToAssignment, o_plotAssignment, o_create_subarray_partition
% Subfunctions: None
% MAT-files required: none
%
% See also: CBG_creationArrayGA , CBG_CA_Position_Objective_optim_ga, ...
%           CBG_geneToAssignment, o_create_subarray_partition

%------------- BEGIN CODE --------------

% We are going to find it
sol_found = true;

% Localize variables
problem.nUsers = length(candSet);
problem.candSet = candSet;

% Create subarray partition
problem = o_create_subarray_partition(problem);
problem.NzPatch = problem.NxPatch;
problem.dz = problem.dx;

% Create the antenna handler and the data structure with all possible pos.
problem.handle_Ant = phased.CosineAntennaElement('FrequencyRange',...
                       [problem.freq-(problem.Bw/2) problem.freq+(problem.Bw/2)],...
                       'CosinePower',[1.5 2.5]); % [1.5 2.5] values set porque si
handle_ConformalArray = phased.URA([problem.NyPatch,problem.NzPatch],...
                        'Lattice','Rectangular','Element',problem.handle_Ant,...
                        'ElementSpacing',[problem.dy,problem.dz]);
problem.possible_locations = handle_ConformalArray.getElementPosition;

% Allocate number of antennas to users (QoS)
problem = o_compute_antennas_per_user(problem,candSet);

if conf.verbosity >= 1
    fprintf('We distribute %d antennas amongst users\n',problem.N_Antennas)
end

% Create the initial genes based on a random assignation
InitialPopulation  = CBG_creationArrayGA(problem,conf);

% Start optimization
[myGene,~,bestScores,~,~,~,~] = CBG_CA_Position_Objective_optim_ga(conf,problem,InitialPopulation);

[handle_Conf_Array,W,DirOK,DirNOK,~,~] = CBG_geneToAssignment(myGene,problem,conf);

% Parse final results
DirNOK_lin = db2pow(DirNOK);
DirNOK_pcvd_lin = sum(DirNOK_lin,1).';
I = pow2db(DirNOK_pcvd_lin);
PRx = DirOK;

if conf.plotAssignmentInitialAndFinal
    o_plotAssignment(problem,handle_Conf_Array);
    % plot of initial values, lb,ub and optimized values.
    f = figure;
    plot(X0,'DisplayName','X0');hold on;plot(myGene,'DisplayName','x');plot(ub,'DisplayName','ub');plot(lb,'DisplayName','lb');hold off;
    disp('Program paused, press any key to continue')
    pause
    if isvalid(f)
        close(f)
    end
end



% EOF