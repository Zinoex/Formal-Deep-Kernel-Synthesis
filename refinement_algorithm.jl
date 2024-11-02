
using Base.Threads
using LinearAlgebra
using SpecialFunctions
# using PyCall
using JLD
# @pyimport numpy

function refine_check(res, q_question, n_best, num_dfa_states, p_action_diff, p_in_diff; dfa_init_state=1)
    # this returns the n_best regions to refine by assessing the difference between upper and lower probability of
    # satisfying as well as outgoing transition probability

    indVmin = res[:, 3]
    indVmax = res[:, 4]

    maxPrs = indVmax[dfa_init_state:num_dfa_states:end]
    minPrs = indVmin[dfa_init_state:num_dfa_states:end]

    # determine which states to refine
    theta = zeros(length(q_question))

    for (idx, s) in enumerate(q_question)
        sat_prob = (maxPrs[s] - minPrs[s])

        i_pimdp = (s-1)*num_dfa_states + dfa_init_state
        p_actions = p_action_diff[i_pimdp]  # + p_in_diff[s]  # outgoing transitions

        theta[idx] = p_actions * sat_prob
    end

#     for (idx, s) in enumerate(q_question)
#         sat_prob = (minPrs[s] - maxPrs[s])
#
#         i_pimdp = (s-1)*num_dfa_states + dfa_init_state
#         p_actions = p_in_diff[s]  # incoming transitions
#
#         theta[idx] = p_actions * sat_prob
#     end

    n_best = min(n_best, length(q_question))
    refine_idx = sortperm(theta)[1:n_best]
    refine_regions = []
    for i in refine_idx
        append!(refine_regions, [q_question[i]])
    end

    refine_regions = sort(refine_regions)
    return refine_regions
end


function refinement_algorithm(refine_states, extents, modes, num_dims, global_dir_name, nn_bounds_dir, refinement;
                              threshold=1e-5, just_gp=false, reuse_dims=false)

    # load prior info

    if !just_gp
        linear_transforms = npzread(nn_bounds_dir * "/linear_trans_m_1_$(refinement).npy")
        linear_bias = npzread(nn_bounds_dir * "/linear_trans_b_1_$(refinement).npy")
        linear_bounds = npzread(nn_bounds_dir*"/linear_bounds_1_$(refinement).npy")
        for mode in 2:num_modes
            linear_transforms = cat(linear_transforms, npzread(nn_bounds_dir * "/linear_trans_m_$(mode)_$(refinement).npy"), dims=6)
            linear_bias = cat(linear_bias, npzread(nn_bounds_dir * "/linear_trans_b_$(mode)_$(refinement).npy"), dims=5)
            linear_bounds = cat(linear_bounds, npzread(nn_bounds_dir * "/linear_bounds_$(mode)_$(refinement).npy"), dims=4)
        end
    else
        linear_transforms = 1
        linear_bias = 1
        linear_bounds = npzread(nn_bounds_dir*"/linear_bounds_1_$(refinement).npy")
        for mode in 2:num_modes
            linear_bounds = cat(linear_bounds, npzread(nn_bounds_dir * "/linear_bounds_$(mode)_$(refinement).npy"), dims=4)
        end
    end
    # TODO, need to figure out how to do this in parallel
    keep_states = []
    for i in 1:size(extents)[1]-1
        if i in refine_states
            continue
        else
            push!(keep_states, i)
        end
    end

    kept = length(keep_states)
    new_extents = nothing
    new_transforms = []
    new_bias = []
    new_linear_bounds = []
    num_added = 0
    dim_list = collect(1:num_dims)

    dims_refined = Dict()
    using_selected_dims = false
    if reuse_dims && isfile(global_exp_dir * "/dims_refined_$(refinement).jld")
        dims_refined = load(global_exp_dir * "/dims_refined_$(refinement).jld", "dims_refined")
        using_selected_dims = true
    end

    smallest_dim = Dict()
    for i in dim_list
        smallest_dim[i] = 9e9
    end

    for idx in refine_states
        # find which dimensions have the largest growth
        if using_selected_dims
            # this is to compare policies on different models, ensures identical discretization
            refine_dim = dims_refined[idx]
        else
            refine_dim = dim_checker(extents[idx, :, :], linear_transforms, modes, idx, dim_list, threshold, just_gp)
            dims_refined[idx] = refine_dim
        end
        # split the extent along that dimensions
        new_regions, smallest_dim = extent_splitter(extents[idx, :, :], refine_dim, threshold, smallest_dim)
        if isnothing(new_extents)
            new_extents = new_regions
        else
            new_extents = vcat(new_extents, new_regions)
        end

        # get the NN posterior for the new regions
        repeats = size(new_regions)[1]
        for sub_idx in 1:repeats
            if !just_gp
                temp = size(linear_transforms)
                added_transform = reshape(linear_transforms[idx,:,:,:,:,:], (1, temp[2], temp[3], temp[4] ,temp[5], temp[6]))
                new_transforms = cat(new_transforms, added_transform, dims=1)

                temp = size(linear_bias)
                added_bias = reshape(linear_bias[idx,:,:,:,:], (1, temp[2], temp[3], temp[4] ,temp[5]))
                new_bias = cat(new_bias, added_bias, dims=1)
            end
            # use this transform to get bounds with the vertices of the new extents
            temp = new_posts_fnc(new_regions[sub_idx, :, :], linear_transforms, linear_bias, modes, idx, num_dims, just_gp)
            new_linear_bounds = cat(new_linear_bounds, temp, dims=1)
            num_added += 1
        end
    end
    @info "Smallest discretization per dimension: $smallest_dim"
    save(global_exp_dir * "/dims_refined_$(refinement).jld", "dims_refined", dims_refined)
#     dims_refined = load(global_exp_dir * "/dims_refined_$(refinement).jld", "dims_refined")

    specific_extents = collect((kept):(kept+num_added-1))
    @info "Added $(num_added - length(refine_states)) regions"

    # now re-save files for refinement+1
    new_extents = vcat(extents[keep_states, :, :], new_extents)
    domain = reshape(extents[end, :, :], (1, num_dims, 2))
    new_extents = vcat(new_extents, domain)
    npzwrite(global_exp_dir * "/extents_$(refinement+1)", new_extents)

    if !just_gp
        new_transforms = vcat(linear_transforms[keep_states, :, :, :, :, :], new_transforms)
        new_bias = vcat(linear_bias[keep_states, :, :, :, :], new_bias)
    end

    new_linear_bounds = vcat(linear_bounds[keep_states, :, :, :], new_linear_bounds)

    additional_array = zeros(num_added, num_dims, 2)
    gp_bounds_dir = global_exp_dir  * "/gp_bounds"

    for mode in modes

        if !just_gp
            npzwrite(nn_bounds_dir * "/linear_trans_m_$(mode)_$(refinement+1)", new_transforms[:,:,:,:,:,mode])
            npzwrite(nn_bounds_dir * "/linear_trans_b_$(mode)_$(refinement+1)", new_bias[:,:,:,:,mode])
        end

        npzwrite(nn_bounds_dir * "/linear_bounds_$(mode)_$(refinement+1)", new_linear_bounds[:,:,:,mode])

        mean_bound = npzread(gp_bounds_dir*"/mean_data_$(mode)_$refinement.npy")
        mean_bound = vcat(mean_bound[keep_states, :, :], additional_array)
        npzwrite(gp_bounds_dir*"/mean_data_$(mode)_$(refinement+1)", mean_bound)

        sig_bound = npzread(gp_bounds_dir*"/sig_data_$(mode)_$refinement.npy")
        sig_bound = vcat(sig_bound[keep_states, :, :], additional_array)
        npzwrite(gp_bounds_dir*"/sig_data_$(mode)_$(refinement+1)", sig_bound)

        for dim in 1:num_dims
            dim_region_filename = nn_bounds_dir * "/linear_bounds_$(mode)_1_$dim"
            npzwrite(dim_region_filename*"_these_indices_$(refinement+1)", specific_extents)
        end
    end

end


function new_posts_fnc(region, linear_transforms, linear_bias, modes, idx, dims, just_gp)
    x_ranges = [region[k,:] for k in 1:(size(region)[1])]
    vertices = [[vert...] for vert in Base.product(x_ranges...)]

    new_posts = nothing
    for mode in modes
        if just_gp
            lA = 1.
            uA = 1.
            l_bias = zeros(dims)
            u_bias = zeros(dims)
        else
            lA = linear_transforms[idx,1,1,:,:,mode]
            uA = linear_transforms[idx,2,1,:,:,mode]
            l_bias = linear_bias[idx,1,1,:,mode]
            u_bias = linear_bias[idx,2,1,:,mode]
        end

        v_low = nothing
        v_up = nothing
        for vertex in vertices
            l_out = lA * vertex + l_bias
            u_out = uA * vertex + u_bias
            if isnothing(v_low)
                v_low = l_out
                v_up = u_out
            else
                for dim in 1:dims
                    v_low[dim] = min(v_low[dim], l_out[dim])
                    v_up[dim] = max(v_up[dim], u_out[dim])
                end
            end
        end

        if isnothing(new_posts)
            new_posts = vcat(transpose(v_low), transpose(v_up))
        else
            new_posts = cat(new_posts, vcat(transpose(v_low), transpose(v_up)), dims=3)
        end
    end

    test = size(new_posts)
    reshaping = [1]
    for i in 1:length(test)
        push!(reshaping, test[i])
    end

    return reshape(new_posts, reshaping...)

end


function dim_checker(region, linear_transforms, modes, idx, dim_list, threshold, just_gp)
    x_ranges = [region[k,:] for k in 1:(size(region)[1])]
    vertices = [[vert...] for vert in Base.product(x_ranges...)]

    xi_max = 0
    max_dim = nothing
    for mode in modes
        if just_gp
            lA = 1.
            uA = 1.
        else
            lA = linear_transforms[idx,1,1,:,:,mode]
            uA = linear_transforms[idx,2,1,:,:,mode]
        end

        v_low = []
        v_up = []
        for vertex in vertices
            l_out = lA * vertex
            u_out = uA * vertex
            append!(v_low, [l_out])
            append!(v_up, [u_out])
        end

        checked_pairs = []
        for (idx1, v1) in enumerate(vertices)
            for (idx2, v2) in enumerate(vertices)
                if v1 == v2
                    continue
                end

                if (v2, v1) in checked_pairs
                    # don't check pairs of vertices again
                    continue
                end

                matching_dims = findall(in(v1), v2)
                if length(matching_dims) == 0
                    continue
                end

                append!(checked_pairs, [(v1, v2)])

                vertex_norm = norm(v1 - v2)
                upper_norm = norm(v_up[idx1] - v_low[idx2])
                lower_norm = norm(v_low[idx1] - v_up[idx2])

                xi_a = max(upper_norm / vertex_norm, lower_norm / vertex_norm)
                if xi_a > xi_max
                    used_dims = copy(dim_list)
                    for i in reverse(sort(matching_dims))
                        splice!(used_dims, i)
                    end
                    # ensure this dimension can be refined first
                    actually_valid = copy(used_dims)
                    for split_dim in used_dims
                        dx = region[split_dim,2] - region[split_dim,1]
                        if dx/2.0 < threshold
                            filter!(x -> x != split_dim, actually_valid)
                        end
                    end

                    if length(actually_valid) > 0
                        xi_max = xi_a
                        max_dim = copy(actually_valid)
                    end
                end
            end
        end
    end

    return max_dim
end


function extent_splitter(extent, refine_dims, threshold, smallest_dim)

    num_dims = size(extent)[1]
    grid_size = []
    num_new = 1
    for dim in 1:num_dims
        dx = extent[dim, 2] - extent[dim, 1]
        if dim in refine_dims
            if (dx/2.0 >= threshold)
                dx /= 2.0
                num_new *= 2
            end
        end

        if dx < smallest_dim[dim]
            smallest_dim[dim] = dx
        end

        push!(grid_size, dx)
    end

    # now I have the grid size, figure out how to split the space according to that grid
    dim_ranges = [collect(extent[dim, 1]:grid_size[dim]:extent[dim, 2]) for dim in 1:num_dims]
    temp = [[[dim_ranges[dim][i], dim_ranges[dim][i+1]] for i in 1:(length(dim_ranges[dim]) - 1)] for dim in 1:num_dims]
    state_extents = (Base.product(temp...))

    discrete_sets = zeros(num_new, num_dims, 2)
    for (i, state) in enumerate(state_extents)
        for j in 1:size(extent)[1]
            discrete_sets[i, j, :] = state[j]
        end
    end
    return discrete_sets[:, :, :], smallest_dim

end


function refinement_algorithm_error_gp(refine_states, extents, modes, num_dims, global_dir_name, nn_bounds_dir, refinement;
                                       threshold=1e-5, reuse_dims=false)
    # load prior info
    linear_transforms = npzread(nn_bounds_dir * "/linear_trans_m_1_$(refinement).npy")
    linear_bias = npzread(nn_bounds_dir * "/linear_trans_b_1_$(refinement).npy")
    linear_bounds = npzread(nn_bounds_dir*"/linear_bounds_1_$(refinement).npy")
    for mode in 2:num_modes
        linear_transforms = cat(linear_transforms, npzread(nn_bounds_dir * "/linear_trans_m_$(mode)_$(refinement).npy"), dims=6)
        linear_bias = cat(linear_bias, npzread(nn_bounds_dir * "/linear_trans_b_$(mode)_$(refinement).npy"), dims=5)
        linear_bounds = cat(linear_bounds, npzread(nn_bounds_dir * "/linear_bounds_$(mode)_$(refinement).npy"), dims=4)
    end

    linear_transforms_gp = 1
    linear_bias_gp = 1
    linear_bounds_gp = npzread(nn_bounds_dir*"/linear_bounds_gp_1_$(refinement).npy")
    for mode in 2:num_modes
        linear_bounds_gp = cat(linear_bounds_gp, npzread(nn_bounds_dir * "/linear_bounds_gp_$(mode)_$(refinement).npy"), dims=4)
    end

    # TODO, need to figure out how to do this in parallel
    keep_states = []
    for i in 1:size(extents)[1]-1
        if i in refine_states
            continue
        else
            push!(keep_states, i)
        end
    end

    kept = length(keep_states)
    new_extents = nothing
    new_transforms = []
    new_bias = []
    new_linear_bounds = []
    new_linear_bounds_gp = []
    num_added = 0
    dim_list = collect(1:num_dims)

    dims_refined = Dict()
    using_selected_dims = false
    if reuse_dims && isfile(global_exp_dir * "/dims_refined_$(refinement).jld")
        dims_refined = load(global_exp_dir * "/dims_refined_$(refinement).jld", "dims_refined")
        using_selected_dims = true
    end

    smallest_dim = Dict()
    for i in dim_list
        smallest_dim[i] = 9e9
    end

    for idx in refine_states
        # find which dimensions have the largest growth
        if using_selected_dims
            # this is to compare policies on different models, ensures identical discretization
            refine_dim = dims_refined[idx]
        else
            refine_dim = dim_checker(extents[idx, :, :], linear_transforms, modes, idx, dim_list, threshold, false)
            dims_refined[idx] = refine_dim
        end
        # split the extent along that dimensions
        new_regions, smallest_dim = extent_splitter(extents[idx, :, :], refine_dim, threshold, smallest_dim)
        if isnothing(new_extents)
            new_extents = new_regions
        else
            new_extents = vcat(new_extents, new_regions)
        end

        # get the NN posterior for the new regions
        repeats = size(new_regions)[1]
        for sub_idx in 1:repeats
            temp = size(linear_transforms)
            added_transform = reshape(linear_transforms[idx,:,:,:,:,:], (1, temp[2], temp[3], temp[4] ,temp[5], temp[6]))
            new_transforms = cat(new_transforms, added_transform, dims=1)

            temp = size(linear_bias)
            added_bias = reshape(linear_bias[idx,:,:,:,:], (1, temp[2], temp[3], temp[4] ,temp[5]))
            new_bias = cat(new_bias, added_bias, dims=1)

            # use this transform to get bounds with the vertices of the new extents
            temp = new_posts_fnc(new_regions[sub_idx, :, :], linear_transforms, linear_bias, modes, idx, num_dims, false)
            new_linear_bounds = cat(new_linear_bounds, temp, dims=1)

            temp = new_posts_fnc(new_regions[sub_idx, :, :], linear_transforms, linear_bias, modes, idx, num_dims, true)
            new_linear_bounds_gp = cat(new_linear_bounds_gp, temp, dims=1)
            num_added += 1
        end
    end
    @info "Smallest discretization per dimension: $smallest_dim"
    save(global_exp_dir * "/dims_refined_$(refinement).jld", "dims_refined", dims_refined)

    specific_extents = collect((kept):(kept+num_added-1))
    @info "Added $(num_added - length(refine_states)) regions"

    # now re-save files for refinement+1
    new_extents = vcat(extents[keep_states, :, :], new_extents)
    domain = reshape(extents[end, :, :], (1, num_dims, 2))
    new_extents = vcat(new_extents, domain)
    npzwrite(global_exp_dir * "/extents_$(refinement+1)", new_extents)

    new_transforms = vcat(linear_transforms[keep_states, :, :, :, :, :], new_transforms)
    new_bias = vcat(linear_bias[keep_states, :, :, :, :], new_bias)

    new_linear_bounds = vcat(linear_bounds[keep_states, :, :, :], new_linear_bounds)
    new_linear_bounds_gp = vcat(linear_bounds_gp[keep_states, :, :, :], new_linear_bounds_gp)

    additional_array = zeros(num_added, num_dims, 2)
    gp_bounds_dir = global_exp_dir  * "/gp_bounds"

    for mode in modes

        npzwrite(nn_bounds_dir * "/linear_trans_m_$(mode)_$(refinement+1)", new_transforms[:,:,:,:,:,mode])
        npzwrite(nn_bounds_dir * "/linear_trans_b_$(mode)_$(refinement+1)", new_bias[:,:,:,:,mode])

        npzwrite(nn_bounds_dir * "/linear_bounds_$(mode)_$(refinement+1)", new_linear_bounds[:,:,:,mode])
        npzwrite(nn_bounds_dir * "/linear_bounds_gp_$(mode)_$(refinement+1)", new_linear_bounds_gp[:,:,:,mode])

        mean_bound = npzread(gp_bounds_dir*"/mean_data_$(mode)_$refinement.npy")
        mean_bound = vcat(mean_bound[keep_states, :, :], additional_array)
        npzwrite(gp_bounds_dir*"/mean_data_$(mode)_$(refinement+1)", mean_bound)

        sig_bound = npzread(gp_bounds_dir*"/sig_data_$(mode)_$refinement.npy")
        sig_bound = vcat(sig_bound[keep_states, :, :], additional_array)
        npzwrite(gp_bounds_dir*"/sig_data_$(mode)_$(refinement+1)", sig_bound)

        for dim in 1:num_dims
            dim_region_filename = nn_bounds_dir * "/linear_bounds_$(mode)_1_$dim"
            npzwrite(dim_region_filename*"_these_indices_$(refinement+1)", specific_extents)
        end
    end

end
