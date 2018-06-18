
function convert_all_for_one_stimuli_type (fluorescence_trace_type,...
    stimulus, raster_dir_name, nwb_dir_name)
tic

manifests = get_manifests_info_from_api();

boc = brain_observatory_cache(manifests);

boc = boc.filter_sessions_by_stimuli(stimulus);

already_converted = 0;
for iSession = 1: size(boc.filtered_session_table.id, 1)
    
    session_id = boc.filtered_session_table.id(iSession);
    
    convert_fluorescenece_trace_into_raster_format(fluorescence_trace_type,session_id,...
    stimulus, raster_dir_name, nwb_dir_name)
already_converted + 1
end
toc
end

