
using Distributed

args = ARGS
addprocs(parse(Int, args[1]))

include("imdp_construction.jl")
include("bound_gp_outputs.jl")
include("visualize.jl")
include("dynamics.jl")
include("refinement_algorithm.jl")

@pyimport pickle

EXPERIMENT_DIR = @__DIR__
experiment_type = "/deep_kernel_synthesis"
exp_dir = EXPERIMENT_DIR * experiment_type

experiment_number = parse(Int, args[2])
refinements = parse(Int, args[3])
skip_labels = [nothing]
just_gp = false
refine_threshold = 1e-5

reuse_bounds = true  # feel free to edit any of these
reuse_pimdp = true
reuse_policy = true
reuse_refinement = true
prob_plot = true

compare_policies = false  # KEEP THIS AS FALSE UNLESS YOU HAVE POLICIES AND REFINEMENTS STORED IN THE PROPER FOLDER
use_color_wheel = false

if experiment_number == 0
    global_dir_name = "sys_2d_lin"
    dyn_noise = [0.1, 0.1]  # this is std dev of process noise
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid", "r"))
    unsafe_set = [nothing]
    goal_set = [[[-1., 1.], [-1., 1.]]]
    labels = Dict("b" => unsafe_set, "a" => goal_set)
elseif experiment_number == 1
    global_dir_name = "sys_2d"
    dyn_noise = [0.01, 0.01]  # this is std dev of process noise
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid_complex", "r"))
    dyn_modes = sys_2d_dynamics(dyn_noise[1])
    unsafe_set = [[[-1.75, -1.25], [-0.75, 1.0]],
                  [[-1.0, -0.5], [-1.25, -0.875]],
                  [[0.5, 1.125], [-1.75, -1.25]],
                  [[0.75, 1.0], [-0.5, 0.5]],
                  [[0.75, 1.75], [0.75, 1.75]]]
    goal_a = [[[-0.75, 0.75], [-0.75, 0.75]]]
    goal_c = [[[-1.75, 0.0], [-2.0, -1.5]],
              [[1.125, 2.0], [-1.75, 0.0]],
              [[-1.25, 0.0], [1.0, 1.875]]]
    labels = Dict("b" => unsafe_set, "a" => goal_a, "c" => goal_c)
    skip_labels = ["b∧!a∧!c"]
    use_color_wheel = true
elseif experiment_number == 2
    global_dir_name = "sys_2d_gp"
    dyn_noise = [0.01, 0.01]  # this is std dev of process noise
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid_complex", "r"))
    dyn_modes = sys_2d_dynamics(dyn_noise[1])
    unsafe_set = [[[-1.75, -1.25], [-0.75, 1.0]],
                  [[-1.0, -0.5], [-1.25, -0.875]],
                  [[0.5, 1.125], [-1.75, -1.25]],
                  [[0.75, 1.0], [-0.5, 0.5]],
                  [[0.75, 1.75], [0.75, 1.75]]]
    goal_a = [[[-0.75, 0.75], [-0.75, 0.75]]]
    goal_c = [[[-1.75, 0.0], [-2.0, -1.5]],
              [[1.125, 2.0], [-1.75, 0.0]],
              [[-1.25, 0.0], [1.0, 1.875]]]
    labels = Dict("b" => unsafe_set, "a" => goal_a, "c" => goal_c)
    skip_labels = ["b∧!a∧!c"]
    use_color_wheel = true
elseif experiment_number == 3
    global_dir_name = "dubins_sys"
    dyn_noise = [0.01, 0.01, 0.01]  # this is std dev of process noise
    dyn_modes = sys_3d_dynamics(dyn_noise)
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid", "r"))
    unsafe_set = [[[4., 6], [0., 1.], [-0.5, 0.5]]]
    goal_set = [[[8., 10.], [0., 1.], [-0.5, 0.5]]]
    labels = Dict("b" => unsafe_set, "a" => goal_set)
    prob_plot = false
    skip_labels = ["b∧!a", "a∧!b"]
    refine_threshold = 0.0124 # this is to adjust for numerical errors
    use_color_wheel = false
elseif experiment_number == 4
    global_dir_name = "dubins_sys_gp"
    just_gp = true
    dyn_noise = [0.01, 0.01, 0.01]  # this is std dev of process noise
    dyn_modes = sys_3d_dynamics(dyn_noise)
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid", "r"))
    unsafe_set = [[[4., 6], [0., 1.], [-0.5, 0.5]]]
    goal_set = [[[8., 10.], [0., 1.], [-0.5, 0.5]]]
    labels = Dict("b" => unsafe_set, "a" => goal_set)
    prob_plot = false
    skip_labels = ["b∧!a", "a∧!b"]
    refine_threshold = 0.0124 # this is to adjust for numerical errors
    use_color_wheel = false
elseif experiment_number == 5
    global_dir_name = "sys_5d"
    dyn_noise = [0.05, 0.05, 0.01, 0.01, 0.01]  # this is std dev of process noise
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid", "r"))
    dyn_modes = sys_5d(dyn_noise)
    unsafe_set = [[[-0.75, 0.0], [0.5, 2.0], [-0.3, 0.3], [-0.3, 0.3], [-0.3, 0.3]],
                  [[0.5, 2.0], [-0.75, 0.0], [-0.3, 0.3], [-0.3, 0.3], [-0.3, 0.3]]]
    goal_set = [[[1.0, 2.0], [0.5, 2.0], [-0.3, 0.3], [-0.3, 0.3], [-0.3, 0.3]]]
    labels = Dict("b" => unsafe_set, "a" => goal_set)
    prob_plot = false
    skip_labels = ["b∧!a", "a∧!b"]
    refine_threshold = 0.0124 # this is to adjust for numerical errors
elseif experiment_number == 6
    global_dir_name = "dubins_sys_sd"
    dyn_noise = [0.01, 0.01, 0.01]  # this is std dev of process noise
    dyn_modes = sys_3d_dynamics(dyn_noise)
    dfa = pickle.load(open(EXPERIMENT_DIR * "/dfa_reach_avoid", "r"))
    unsafe_set = [[[4., 6], [0., 1.], [-0.5, 0.5]]]
    goal_set = [[[8., 10.], [0., 1.], [-0.5, 0.5]]]
    labels = Dict("b" => unsafe_set, "a" => goal_set)
    prob_plot = false
    skip_labels = ["b∧!a", "a∧!b"]
    refine_threshold = 0.0124 # this is to adjust for numerical errors
    use_color_wheel = false
end

unsafe_label = "b"

global_exp_dir = exp_dir * "/" * global_dir_name
general_data = npzread(global_exp_dir * "/general_info.npy")
nn_bounds_dir = global_exp_dir * "/nn_bounds"

satisfaction_threshold = .95
n_best = 10000  # TODO, fix this number to something based on the number of states

num_dfa_states = length(dfa["states"])
if !isnothing(dfa["accept"])
    num_dfa_states -= 1
end
if !isnothing(dfa["sink"])
    num_dfa_states -= 1
end

num_modes = general_data[1]
num_dims = general_data[2]
num_sub_regions = general_data[3]
if length(general_data) == 5
    use_single_dim = general_data[5]
else
    use_single_dim = 0
end

for refinement in 0:refinements

    pimdp_filepath = global_exp_dir * "/pimdp_$(refinement).txt"

    extents = npzread(global_exp_dir * "/extents_$refinement.npy")
    num_regions = size(extents)[1] - 1

    @info "The abstraction for refinement $refinement has $num_regions states"

    # define labels for every extent, this can be used to skip bounding obstacle posteriors
    label_fn = label_states(labels, extents, unsafe_label, num_dims, num_regions)

    # Get mean and sig bounds on gp
    @info "Bounding the GP mean and variance"
    reuse_check = reuse_bounds && ((refinement == 0) || reuse_refinement)
    bound_gp(num_regions, num_modes, num_dims, refinement, global_exp_dir, reuse_check, label_fn, skip_labels, use_single_dim)

    # setup imdp structure
    modes = [i for i in 1:num_modes]
    states = [i for i in 1:num_regions+1]
    imdp = IMDPModel(states, modes, nothing, nothing, label_fn, extents)

    res_filepath = global_exp_dir * "/policy_$(refinement)"
    reuse_check = reuse_pimdp && reuse_bounds && ((refinement == 0) || reuse_refinement) && !compare_policies
    if reuse_check && isfile(pimdp_filepath)
        @info "Using saved PIMDP"
        # generate a pimdp model for plotting
        pimdp = fast_pimdp(dfa, imdp, num_regions)
        p_action_diff = npzread(global_exp_dir*"/p_act_diff_$refinement.npy")
        p_in_diff = npzread(global_exp_dir*"/p_in_diff_$refinement.npy")
    else
        @info "Constructing and saving the PIMDP Model"
        res = nothing
        if compare_policies
            res = npzread(res_filepath * ".npy")
        end
        pimdp, p_action_diff, p_in_diff = direct_pimdp_construction(extents, dyn_noise, global_exp_dir, refinement,
                                                                   num_modes, num_regions, num_dims, label_fn,
                                                                   skip_labels, dfa, imdp, pimdp_filepath; res=res)
        npzwrite(global_exp_dir*"/p_act_diff_$refinement", p_action_diff)
        npzwrite(global_exp_dir*"/p_in_diff_$refinement", p_in_diff)
    end

    imdp = nothing

    reuse_check = reuse_policy && reuse_pimdp && reuse_bounds && (refinement < 1 || reuse_refinement) && !compare_policies
    if reuse_check && isfile(res_filepath * ".npy")
        @info "Using saved policy"
        res = npzread(res_filepath * ".npy")
    else
        @info "Running Synthesis"
        accuracy = 1e-6
        if length(dyn_noise) > 3
            # it is too slow on higher dims, allow the upper bound some slack
            accuracy = 1e-3
        end
        syn_runtime = @elapsed begin
            res = run_synthesis(pimdp_filepath, -1, refinement, EXPERIMENT_DIR; ep=accuracy)
        end
        @info "Synthesis took $syn_runtime seconds"
        npzwrite(res_filepath, res)
    end


    # plot results
    plot_dir = global_exp_dir * "/plots"
    if !isdir(plot_dir)
        mkdir(plot_dir)
    end

    @info "Plotting Results"
    obs_key = "b"
    x0 = nothing
    if length(dyn_noise) == 2
        x0 = [[-1.8125, -1.7114], [1.7291, -1.921], [0.5451, 1.7682]]
        x0 = [[-1.8125, -1.7114], [-1.9212, 1.821], [0.5451, 1.7682]]
    elseif length(dyn_noise) == 3
        x0 = [[0.221, 0.213, 0.21]]
        x0 = [[0.221, 0.313, 0.141]]
    elseif length(dyn_noise) == 5
        x0 = [[0.9801, -1.213, 0.001, 0.001, 0.001], [-1.001, -1.213, 0.001, 0.001, 0.001]]
    end

    q_refine = plot_nd_results(res, extents, num_regions, num_dims, plot_dir, dfa, pimdp, refinement;
                               num_dfa_states=num_dfa_states, min_threshold=satisfaction_threshold,
                               labeled_regions=labels, obs_key=unsafe_label, prob_plots=prob_plot, x0=x0,
                               modes=dyn_modes, use_color_wheel=use_color_wheel)

    if refinement < refinements
        reuse_check = reuse_policy && reuse_pimdp && reuse_bounds && reuse_refinement
        if reuse_check && isfile(nn_bounds_dir * "/linear_trans_m_$(num_modes)_$(refinement+1).npy")
            @info "Reusing refined regions"
            print("\n")
        else
            refinement_time = @elapsed begin
                @info "Beginning refinement algorithm"
                refine_filepath = global_exp_dir * "/refine_states_$(refinement)"
                reuse_refine_states = true
                if reuse_refine_states && isfile(refine_filepath * ".npy")
                    refine_states = npzread(refine_filepath * ".npy")
                else
                    refine_states = refine_check(res, q_refine, n_best, num_dfa_states, p_action_diff, p_in_diff; dfa_init_state=1)
                    npzwrite(refine_filepath, refine_states)
                end

                refinement_algorithm(refine_states, extents, modes, num_dims, global_dir_name, nn_bounds_dir, refinement;
                                    threshold=refine_threshold, just_gp=just_gp, reuse_dims=reuse_refine_states)
            end
            @info "Refined regions created in $(refinement_time) seconds"
            print("\n")

        end
    else
        @info "Done!"
    end
end