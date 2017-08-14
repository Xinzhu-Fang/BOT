function convert_fluorescenece_trace_into_raster_format(fluorescence_trace_type,session_id,...
    stimuli, raster_dir_name, nwb_dir_name)
tic 

addpath(genpath(nwb_dir_name))

nwb_name = [num2str(session_id) '.nwb'];

manifests = get_manifests_info_from_api();

boc = brain_observatory_cache(manifests);

boc.filter_sessions_by_session_id(session_id);



% get all fluorescenece_trace from nwb

raw = h5read(nwb_name,'/processing/brain_observatory_pipeline/Fluorescence/imaging_plane_1/data');

neuropil = h5read(nwb_name, '/processing/brain_observatory_pipeline/Fluorescence/imaging_plane_1/neuropil_traces');

demixed = h5read(nwb_name, '/processing/brain_observatory_pipeline/Fluorescence/imaging_plane_1_demixed_signal/data');

contamination_ratio = h5read(nwb_name, '/processing/brain_observatory_pipeline/Fluorescence/imaging_plane_1/r');

contamination_ratio_matrix = contamination_ratio .* eye (size(contamination_ratio,1));

neuropil_matrix = neuropil * contamination_ratio_matrix;

neuropil_corrected = demixed - neuropil_matrix;

DfOverF = h5read(nwb_name,'/processing/brain_observatory_pipeline/DfOverF/imaging_plane_1/data');

all_f_traces = struct('raw', raw, 'demixed', demixed, 'neuropil_correted', neuropil_corrected, 'DfOverF', DfOverF);

fluorescenece_trace = all_f_traces.(fluorescence_trace_type);

% get other info from nwb

sampling_times = h5read(nwb_name,'/processing/brain_observatory_pipeline/DfOverF/imaging_plane_1/timestamps');

stimuli_onset_times = h5read(nwb_name, strcat('/stimulus/presentation/', stimuli, '_stimulus/timestamps'));

new_cell_specimen_ids = h5read(nwb_name, '/processing/brain_observatory_pipeline/ImageSegmentation/cell_specimen_ids');

% create a head directory 'ratser/' that store all ratser formats

if ~exist(raster_dir_name,'dir')
    mkdir(raster_dir_name);
end

% under the head directory 'raster/', create a directory for one stimuli
% type

stimuli_dir_name = [raster_dir_name  stimuli '/'];
if ~exist(stimuli_dir_name, 'dir')
    mkdir(stimuli_dir_name);
end
    
% under the head directory 'raster/', create a current direcotry that store
% all raster formats returned from the current analysis

current_raster_dir_name = [stimuli,'_', num2str(session_id) ,'/'];
current_raster_dir_name_full  = [stimuli_dir_name current_raster_dir_name];

if ~exist(current_raster_dir_name_full ,'dir')
    mkdir(current_raster_dir_name_full );


% fetching some parameters (hardcoded inside the function) that help build the raster data such as window
% frames, sampling frequency, etc.

parameters_for_cur_stimulus = fetch_stimuli_based_parameters(stimuli);

% generate raster_labels, which applys to all cells in the same session

raster_labels = generate_raster_labels (nwb_name, stimuli);

% create raster files

for iCell = 1:size(fluorescenece_trace,2)
    
    cur_new_cell_id = new_cell_specimen_ids(iCell);
    
    cur_raster_file_name = [num2str(cur_new_cell_id), '.mat'];
    % raster_data is a matrix of k dimensions of trials by n dimensions of
    % time
    raster_data = generate_raster_data(iCell, fluorescenece_trace, parameters_for_cur_stimulus, sampling_times, stimuli_onset_times);
    
    raster_site_info = generate_raster_site_info(boc, parameters_for_cur_stimulus,cur_new_cell_id);
    
   
    save([current_raster_dir_name_full , cur_raster_file_name], 'raster_data', 'raster_labels', 'raster_site_info');
    
end

fprintf ( [num2str(size(fluorescenece_trace,2)) ' cells converted into raster formats.'])
disp(' ')
fprintf ([' There are ' num2str(length(dir(current_raster_dir_name_full))-2) ' raster files in folder ' current_raster_dir_name_full])
disp(' ')
toc
else
    fprintf([current_raster_dir_name_full ' already exists'])
end

end % end of convert_fluorescenece_trace_into_raster_format


%  generate raster_data

function raster_data = generate_raster_data(i, fluorescenece_trace, parameters_for_cur_stimulus, sample_times, stimuli_onset_times)

cur_cell_data = fluorescenece_trace (:,i);

% preallocation of cell_matrix: a trial by time matrix of dfOVerF of a
% single cell

cur_cell_matrix = NaN * ones(size(stimuli_onset_times,1), parameters_for_cur_stimulus.sampling_points_after_onset...
    - parameters_for_cur_stimulus.sampling_points_before_onset +1);

onset = 1;
% looking for the closet sampling time to stimuli onset time
for iTrial = 1:size(stimuli_onset_times,1)  %6000
    
    curr_stimulus_onset = stimuli_onset_times(iTrial);
    
    while curr_stimulus_onset - sample_times(onset) > parameters_for_cur_stimulus.sample_interval
        
        onset = onset + 1;
        
    end
    
    cur_cell_matrix (iTrial,:) = cur_cell_data(onset + parameters_for_cur_stimulus.sampling_points_before_onset:...
        onset + parameters_for_cur_stimulus.sampling_points_after_onset, 1)';
    
end
raster_data = cur_cell_matrix;
end

% generate raster_site_info

function raster_site_info = generate_raster_site_info(boc, parameters_for_cur_stimulus,cur_new_cell_id)

raster_site_info = parameters_for_cur_stimulus;

raster_site_info.container_id = boc.container_id;

raster_site_info.new_cell_id = cur_new_cell_id;

raster_site_info.session_id = boc.session_id;

raster_site_info.session_type = boc.session_type;

raster_site_info.targeted_structure = boc.targeted_structure;

raster_site_info.imaging_depth = boc.imaging_depth;

raster_site_info.stimuli_type = boc.stimuli;

raster_site_info = orderfields(raster_site_info);

end

% provide parameters that help build the raster data such as window
% frames, sampling frequency, etc.

function parameters_for_cur_stimulus = fetch_stimuli_based_parameters(stimuli)

% set parameters for raster_data

stimuli_type = {'static_gratings';'drifting_gratings'};

sample_interval = repelem(0.033, length(stimuli_type)).';  % 30 Hz two-photon movie

stimuli_interval = [0.25; 3] ; % stimuli are shown every 250 ms

starts = [-0.25; -0.25]; % window starts 250 ms before stimulus onset

ends = [0.75; 2.75]; % window ends 75o ms after stimulus onset

sampling_points_before_onset = NaN * ones(length(stimuli_type),1); % number of sampling points before the onset of stimuli

for iStimulus_type = 1: length(stimuli_type)
    % total of sampling time points taken before stimulus onset
    sampling_points_before_onset(iStimulus_type) = round(starts(iStimulus_type)/sample_interval(iStimulus_type));
    
end

position_of_sampling_point_at_onset = 1 - sampling_points_before_onset;

sampling_points_after_onset = NaN * ones(length(stimuli_type),1);

for iStimulus_type = 1: length(stimuli_type)
    % total of sampling time points taken after stimulus onset
    sampling_points_after_onset(iStimulus_type) = round(ends(iStimulus_type)/sample_interval(iStimulus_type));
    
end

parameters_for_all_stimuli = table (sample_interval, stimuli_interval, starts, ends, sampling_points_before_onset ...
    , sampling_points_after_onset,position_of_sampling_point_at_onset ,'RowNames', stimuli_type);

parameters_for_cur_stimulus = table2struct(parameters_for_all_stimuli(stimuli,:));

end

% genereate raster_labels

function raster_labels = generate_raster_labels (nwb_name, stimuli)

variables = h5read(nwb_name, strcat('/stimulus/presentation/', stimuli, '_stimulus/features'));

% labels is a matrix of k dimensions of variables by n dimensions of trials
levels = h5read(nwb_name,strcat('/stimulus/presentation/', stimuli, '_stimulus/data'));

% In the case of drifting_gratings, there is this thrid variable called
% blank sweep with two levels 1 and 0, which is redundant and discarded
% here.

if strcmp(stimuli,'drifting_gratings') == 1
    
    variables = variables(1:2,:);
    
    levels = levels(1:2,:);
    
end

%     There were blank sweeps (i.e. mean luminance gray instead of grating)
%     presented roughly once every 25 gratings,
%     which have NaN for all three variables.
%     We are converting the levels matrix into levels cellarray, where numbers are converted to string
%     and NaNs are replaced with "blank"

parsed_levels = cell (size(levels, 1),size(levels, 2));

for iVariable = 1:size(levels, 1)
    
    for iLevel = 1:size(levels, 2)
        
        curr_level = levels(iVariable, iLevel);
        
        if isnan(curr_level)
            
            parsed_levels{iVariable}{iLevel} = 'blank';
            
        else
            parsed_levels{iVariable}{iLevel} = num2str(curr_level);
            
        end
    end
end

variables = cellstr(char(string(variables)));

raster_labels.combined = {'combined'};

for iVariable = 1:size(variables,1)
    
    raster_labels.(char(strcat("stimulus_", variables(iVariable)))) = parsed_levels{iVariable};
    raster_labels.combined = strcat(raster_labels.combined, {'_'}, parsed_levels{iVariable});
    
end
end







