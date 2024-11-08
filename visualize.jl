
using Plots
using ColorSchemes
using Printf


function plot_nd_results(res_mat, extents, num_regions, num_dims, plot_dir, dfa, pimdp, refinement; num_dfa_states=1,
                         min_threshold=0.9, labeled_regions=Dict(), obs_key=nothing, prob_plots=false,
                         state_outlines_flag=false, dfa_init_state=1, x0=nothing, modes=nothing, use_color_wheel=true)

    X = extents[num_regions+1,:,:]
    minx = X[1, 1]
    maxx = X[1, 2]
    miny = X[2, 1]
    maxy = X[2, 2]

    policy = res_mat[:, 2]
    indVmin = res_mat[:, 3]
    indVmax = res_mat[:, 4]

    maxPrs = indVmax[dfa_init_state:num_dfa_states:end]
    minPrs = indVmin[dfa_init_state:num_dfa_states:end]

    global sat_volume = 0
    sat_regions = []
    global unsat_volume = 0
    unsat_regions = []
    global maybe_volume = 0
    maybe_regions = []
    q_refine = []
    for i in 1:size(extents)[1]-1
        max_prob = maxPrs[i]
        min_prob = minPrs[i]

        if max_prob < min_prob
            # this may happen if synthesis is run with a convergence value > 1e-6
            max_prob = min_prob
        end

#         if (max_prob - min_prob) > 0.02
#             # refine any state where the probabilities haven't converged?
#             append!(q_refine, [i])
#         end

        if min_prob >= min_threshold
            # yay this region satisfied
            global sat_volume += volumize(extents[i, :, :], num_dims)
            append!(sat_regions, [i])
        elseif max_prob < min_threshold
            global unsat_volume += volumize(extents[i, :, :], num_dims)
            append!(unsat_regions, [i])
        else
            global maybe_volume += volumize(extents[i, :, :], num_dims)
            append!(maybe_regions, [i])
            append!(q_refine, [i])  # this is the extent number! yay
        end
    end

    total_volume = sat_volume + unsat_volume + maybe_volume
    @info "Qyes = $(length(sat_regions)), Qno = $(length(unsat_regions)), Q? = $(length(maybe_regions))"
    @info "Volume percentage: Qyes = $(sat_volume/total_volume), Qno = $(unsat_volume/total_volume), Q? = $(maybe_volume/total_volume)"

    filename = plot_dir * "/sat_res_$refinement.txt"
    open(filename, "w") do f
        @printf(f, "Qyes = %d, Qno = %d, Q? = %d \n", length(sat_regions), length(unsat_regions), length(maybe_regions))
        @printf(f, "Volume percentage: Qyes = %f, Qno = %f, Q? = %f \n", (sat_volume/total_volume), (unsat_volume/total_volume), (maybe_volume/total_volume))
    end

    if prob_plots
        # Plot the maximum probabilities
        plt_max = plot(aspect_ratio=1,
                    size=(300,300), dpi=300,
                    xlims=[minx, maxx], ylims=[miny, maxy],
                    xtickfont=font(10),
                    ytickfont=font(10),
                    titlefont=font(10),
                    xticks = [minx, 0, maxx],
                    yticks = [miny, 0, maxy],
                    grid=false)
        [plot_cell(extents[i, :, :], maxPrs[i], state_outlines_flag=state_outlines_flag) for i in 1:num_regions] #
        plot!(Plots.Shape([minx, minx, maxx, maxx], [miny, maxy, maxy, miny]), fillalpha=0, linecolor=:black, linewidth=2, label="")
        savefig(plt_max, plot_dir * "/max_prob.png")

        # Plot the minimum probabilities
        plt_min = plot(aspect_ratio=1,
                    size=(300,300), dpi=300,
                    xlims=[minx, maxx], ylims=[miny, maxy],
                    xtickfont=font(10),
                    ytickfont=font(10),
                    titlefont=font(10),
                    xticks = [minx, 0, maxx],
                    yticks = [miny, 0, maxy],
                    grid=false,
                    backgroundcolor=128)
        [plot_cell(extents[i, :, :], minPrs[i], state_outlines_flag=state_outlines_flag) for i in 1:num_regions] #
        plot!(Plots.Shape([minx, minx, maxx, maxx], [miny, maxy, maxy, miny]), fillalpha=0, linecolor=:black, linewidth=2, label="")
        savefig(plt_min, plot_dir * "/min_prob.png")
    end

    plt_verification = plot(aspect_ratio=1,
                            size=(300,300), dpi=300,
                            xlims=[minx, maxx], ylims=[miny, maxy],
                            xtickfont=font(10),
                            ytickfont=font(10),
                            titlefont=font(10),
                            xticks = [minx, 0, maxx],
                            yticks = [miny, 0, maxy],
                            grid=false,
                            backgroundcolor=128)

    # Plot the cells
    plot_cell_verify(extents[end, :, :], 0.0, 0.0, min_threshold, state_outlines_flag=state_outlines_flag)

    plotted_xy = Dict()
    for i in maybe_regions
        xy = extents[i, 1:2, :]
        if any([xy == key for key in keys(plotted_xy)])
            if minPrs[i] > plotted_xy[xy]
                plot_cell_verify(extents[i, :, :], minPrs[i], maxPrs[i], min_threshold, state_outlines_flag=state_outlines_flag, use_color_wheel=use_color_wheel)
                plotted_xy[xy] = minPrs[i]
            else
                continue
            end
        else
            plot_cell_verify(extents[i, :, :], minPrs[i], maxPrs[i], min_threshold, state_outlines_flag=state_outlines_flag, use_color_wheel=use_color_wheel)
            plotted_xy[xy] = minPrs[i]
        end
    end

    plotted_xy = []
    for i in sat_regions
        xy = extents[i, :, :]
        if any([xy == plotted_xy[idx] for idx in 1:length(plotted_xy)])
            continue
        else
            plot_cell_verify(extents[i, :, :], minPrs[i], maxPrs[i], min_threshold, state_outlines_flag=state_outlines_flag)
            push!(plotted_xy, xy)
        end
    end
    plot!(Plots.Shape([minx, minx, maxx, maxx], [miny, maxy, maxy, miny]), fillalpha=0, linecolor=:black, linewidth=2, label="")

    # fill obstacles with black
    obs = labeled_regions[obs_key]
    for region in obs
        if isnothing(region)
            continue
        end
        plot_obs(region)
    end

    # Plot extents with labels
    for key in keys(labeled_regions)
        one_label = labeled_regions[key]
        for region in one_label
            if isnothing(region)
                continue
            end
            plot_labelled_extent_outline(region, key)
        end
    end

    savefig(plt_verification, plot_dir * "/synthesis_results_$(refinement).png")

    if !isnothing(x0)
        @info "Generating trajectories..."
        # generate trajectories for each initial state in the x0 array
        dfa_states = sort(dfa["states"])
        states_sans_ends = copy(dfa_states)
        dfa_acc_state = dfa["accept"]
        dfa_sink_state = dfa["sink"]

        sizeQ = length(dfa_states)
        if !isnothing(dfa_acc_state)
            sizeQ -= 1
            filter!(x -> x != dfa_acc_state, states_sans_ends)
        end

        if !isnothing(dfa_sink_state)
            sizeQ -= 1
            filter!(x -> x != dfa_sink_state, states_sans_ends)
        end

        dfa_num_map = Dict()
        for i in 1:length(states_sans_ends)
            dfa_num_map[states_sans_ends[i]] = i
        end

        max_steps = 1000

        test_accuracy = true
        if test_accuracy
            success = 0.0
            num_tests = 1000
            for initial_state in x0

                s = 75
                count = 0
                for i in 1:size(extents)[1]-1
                    max_prob = maxPrs[i]
                    min_prob = minPrs[i]
                    if 0.2 > min_prob > 0.1
                        @info [min_prob, max_prob]
                        s = i
                        break
                    end
                end

                region = extents[s, :, :]
                @info "Region: $region"
                x = [region[d,1] + (region[d,2] - region[d,1])*rand() for d in 1:3]

                # simulate 1000 times and find success rate
                s = which_extent(extents, x, num_regions, num_dims)
                q_init = delta_(1, dfa, pimdp.labels[s])
                q = q_init
                @info "Min satisfaction prob at this state is $(indVmin[(s-1)*sizeQ + (dfa_num_map[q])])."
                @info "Max satisfaction prob at this state is $(indVmax[(s-1)*sizeQ + (dfa_num_map[q])])."
                for _ in 1:1000
                    x = [region[d,1] + (region[d,2] - region[d,1])*rand() for d in 1:3] # copy(initial_state)
                    s = which_extent(extents, x, num_regions, num_dims)
                    q = copy(q_init)
                    traj_done = false
                    steps = 1
                    while !traj_done
                        row_idx = (s-1)*sizeQ + (dfa_num_map[q])
                        action = floor(Int, policy[row_idx])
                        f = modes[action]
                        x = f(x)

                        s = which_extent(extents, x, num_regions, num_dims)
                        if s == num_regions+1
                            @info "Trajectory left the domain: $x"
                            break
                        end
                        q = delta_(q, dfa, pimdp.labels[s])

                        if q == dfa_acc_state
                            success += 1.0
                            traj_done = true
                        elseif q == dfa_sink_state
                            traj_done = true
                        elseif steps > max_steps
                            traj_done = true
                        else
                            steps += 1
                        end
                    end
                end
            end

            @info "Simulated success rate is $(success/1000.0)"

        else

            for initial_state in x0
                x_vec = [initial_state[1]]
                y_vec = [initial_state[2]]
                x = initial_state
                s = which_extent(extents, x, num_regions, num_dims)
                q_init = delta_(1, dfa, pimdp.labels[s])
                q = q_init
                traj_done = false
                steps = 1
                while !traj_done
                    row_idx = (s-1)*sizeQ + (dfa_num_map[q])
                    action = floor(Int, policy[row_idx])
                    f = modes[action]
                    x = f(x)

                    s = which_extent(extents, x, num_regions, num_dims)
                    if s == num_regions+1
                        @info "Trajectory left the domain: $x"
                        break
                    end
                    q = delta_(q, dfa, pimdp.labels[s])

                    if q == dfa_acc_state
                        @info "Trajectory is successful!"
                        append!(x_vec, [x[1]])
                        append!(y_vec, [x[2]])
                        traj_done = true
                    elseif q == dfa_sink_state
                        @info "Trajectory violates the specification D:"
                        traj_done = true
                    elseif steps > max_steps
                        @info "Trajectory doesn't end after $max_steps steps..."
                        traj_done = true
                    else
                        append!(x_vec, [x[1]])
                        append!(y_vec, [x[2]])
                        steps += 1
                    end
                end

                scatter!([x_vec[1]], [y_vec[1]], color=:black, markershape=:circle, label="")
                plot!(x_vec, y_vec, color=:black, label="", linewith=2)
                scatter!([x_vec[end]], [y_vec[end]], color=:purple, markershape=:star5, label="")
            end
            savefig(plt_verification, plot_dir * "/trajectories_results_$(refinement).png")
        end
    end

    return q_refine
end


function volumize(region, num_dims)
    total_volume = 1.
    for i in 1:num_dims
        edge = region[i, 2] - region[i, 1]
        total_volume *= edge
    end
    return total_volume
end


function plot_obs(extent; color=:black, fill=1.)
    x = [extent[1][1], extent[1][1], extent[1][2], extent[1][2]]
    y = [extent[2][1], extent[2][2], extent[2][2], extent[2][1]]
    shape = Plots.Shape(x, y)
    plot!(shape, color=color, fillalpha=fill, linecolor=:black, linewidth=1, label="")
end


function plot_labelled_extent_outline(extent, label; color=:white)
    x = [extent[1][1], extent[1][1], extent[1][2], extent[1][2]]
    y = [extent[2][1], extent[2][2], extent[2][2], extent[2][1]]
    shape = Plots.Shape(x, y)
    plot!(shape, fillalpha=0, linecolor=:black, linewidth=1, label="")
    annotate!((extent[1][1]+extent[1][2])/2, (extent[2][1]+extent[2][2])/2, text(label, color, :center, 10,))
end


function plot_cell(extent, prob_value; state_outlines_flag=false, color=:black)
    x = [extent[1, 1], extent[1, 1], extent[1, 2], extent[1, 2]]
    y = [extent[2, 1], extent[2, 2], extent[2, 2], extent[2, 1]]
    shape = Plots.Shape(x, y)
    linealpha = state_outlines_flag ? 1.0 : 0.0
    plot!(shape, color=color, fillalpha=1-prob_value, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
end


function plot_cell_verify(extent, min_prob_value, max_prob_value, threshold; state_outlines_flag=false, use_color_wheel=true)
    if max_prob_value < min_prob_value
        # this may happen if synthesis is run with a convergence value > 1e-6
        max_prob_value = min_prob_value
    end
    x = [extent[1, 1], extent[1, 1], extent[1, 2], extent[1, 2]]
    y = [extent[2, 1], extent[2, 2], extent[2, 2], extent[2, 1]]
    shape = Plots.Shape(x, y)

    linealpha = state_outlines_flag ? 1.0 : 0.0

    color_wheel = cgrad([:red, :yellow2, :green], [0, 0.5, 1])
    if min_prob_value >= threshold
        plot!(shape, color=:white, fillalpha=1, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
        plot!(shape, color=get(color_wheel, 1), fillalpha=0.8, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
    elseif max_prob_value < threshold
        plot!(shape, color=get(color_wheel, 0), fillalpha=0.8, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
    else
        plot!(shape, color=:white, fillalpha=1, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
        if use_color_wheel
            plot!(shape, color=get(color_wheel, min_prob_value), fillalpha=0.8, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
        else
            plot!(shape, color=:yellow2, fillalpha=0.8, linewidth=1, linecolor=:black, linealpha=linealpha, foreground_color_border=:white, foreground_color_axis=:white, label="")
        end
    end
end


function which_extent(extents, x, num_regions, num_dims)
    for idx in 1:(num_regions::Int)
        extent = extents[idx, :, :]
        in_extent = true
        for dim in 1:(num_dims::Int)
            if !(extent[dim, 1] < x[dim] <= extent[dim, 2])
                in_extent = false
                break
            end
        end
        if in_extent
            return idx
        end
    end
    return num_regions+1
end
