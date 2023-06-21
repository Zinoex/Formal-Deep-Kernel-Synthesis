# using Distributed
using SparseArrays

@everywhere using PosteriorBounds
using PyCall
using SharedArrays
@everywhere include("quad_prog_bnb.jl")
@pyimport numpy

function bound_gp(num_regions, num_modes, num_dims, refinement, global_exp_dir, reuse_regions)
    nn_bounds_dir = global_exp_dir * "/nn_bounds"
    for mode in 1:num_modes
        if isfile(global_exp_dir*"/complete_$mode" * "_$refinement.npy") && reuse_regions
            @info "moving to next mode"
            continue
        end

        if refinement > 0
            mean_bound = numpy.load(global_exp_dir*"/mean_data_$mode" * "_$refinement.npy")
            mean_bound = convert(SharedArray, mean_bound)
            sig_bound = numpy.load(global_exp_dir*"/sig_data_$mode" * "_$refinement.npy")
            sig_bound = convert(SharedArray, sig_bound)
        else
            mean_bound = SharedArray(zeros(num_regions, num_dims, 2))
            sig_bound = SharedArray(zeros(num_regions, num_dims, 2))
        end

        linear_bounds = numpy.load(nn_bounds_dir*"/linear_bounds_$mode"*"_$refinement.npy")
        convert(SharedArray, linear_bounds)

        mode_runtime = @elapsed begin
            for dim in 1:(num_dims::Int)
                dim_sig = dyn_noise[dim]
                # load all the data for this mode
                dim_region_filename = nn_bounds_dir * "/linear_bounds_$mode" * "_1" * "_$dim"

                specific_extents = numpy.load(dim_region_filename*"_these_indices_$refinement.npy")  # need to add 1 to this
                x_gp = numpy.load(dim_region_filename*"_x_gp.npy")
                theta_vec = numpy.load(dim_region_filename*"_theta_vec.npy")
                theta_vec_2 = numpy.load(dim_region_filename*"_theta_vec_2.npy")
                K = numpy.load(dim_region_filename*"_K.npy")
                K_inv = numpy.load(dim_region_filename*"_K_inv.npy")
                alpha = numpy.load(dim_region_filename*"_alpha.npy")
                K_inv_scaled = numpy.load(dim_region_filename*"_K_inv_s.npy")
                kernel_info = numpy.load(dim_region_filename*"_kernel.npy")
                out2 = kernel_info[1]
                l2 = kernel_info[2]

                noise = K[1,1] - out2
                cK_inv_scaled = PosteriorBounds.scale_cK_inv(K, out2, noise)

                m = size(x_gp, 2) # n_obs
                n = size(x_gp, 1) # dims
                gp_neg = PosteriorBounds.PosteriorGP(n, m, x_gp, K, Matrix{Float64}(undef, m, m),
                        PosteriorBounds.UpperTriangular(zeros(m,m)), K_inv, -alpha,
                        PosteriorBounds.SEKernel(out2, l2))
                gp = PosteriorBounds.PosteriorGP(n, m, x_gp, K, Matrix{Float64}(undef, m, m),
                        PosteriorBounds.UpperTriangular(zeros(m,m)), K_inv, alpha,
                        PosteriorBounds.SEKernel(out2, l2))
                PosteriorBounds.compute_factors!(gp)

                # parallelize getting mean bounds and variance bounds
                 @sync @distributed for idx in specific_extents
                    # need distributed here because it is significant computation, threading is inefficient
                    x_L = linear_bounds[idx+1, 1, :]
                    x_U = linear_bounds[idx+1, 2, :]

                    # get lower mean bounds
                    mean_info_l = PosteriorBounds.compute_μ_bounds_bnb(gp, x_L, x_U, theta_vec_2,
                                                                       theta_vec; max_iterations=100,
                                                                       bound_epsilon=1e-3, max_flag=false,
                                                                       prealloc=nothing)

                    # get upper mean bounds, negating alpha allows for the "min" to be the -max
                    mean_info_u = PosteriorBounds.compute_μ_bounds_bnb(gp_neg, x_L, x_U, theta_vec_2,
                                                                       theta_vec; max_iterations=100,
                                                                       bound_epsilon=1e-3, max_flag=false,
                                                                       prealloc=nothing)

                    mean_bound[idx+1, dim, 1] = mean_info_l[2]
                    mean_bound[idx+1, dim, 2] = -mean_info_u[2]

                    # get upper bounds on variance
                    sig_check = sig_bound[idx+1, dim, 2]
                    if refinement > 0 && sig_check <= 0*sqrt(dim_sig)
                        # if previous sigma bounds were already small, don't waste time finding better ones
                        sig_ = sig_check
                    else
                        sig_info = PosteriorBounds.compute_σ_bounds(gp, x_L, x_U, theta_vec_2, theta_vec,
                                                                    cK_inv_scaled; max_iterations=20,
                                                                    bound_epsilon=1e-3, min_flag=false,
                                                                    prealloc=nothing)

                        sig_ = sqrt(sig_info[3])  # this is a std deviation
                        sig_low = sqrt(sig_info[2])
                        if abs(sig_-sig_low) > sqrt(1e-3)
                            # this means it didn't converge properly, use expensive quadratic program to find solution
                            outputs = sigma_bnb(gp, x_gp, m, n, out2, x_L, x_U, theta_vec, K_inv_scaled;
                                                max_iterations=20, bound_epsilon=sqrt(1e-3))

                            sig_ = outputs[3]
                        end
                    end

                    sig_bound[idx+1, dim, 2] = sig_
                    sig_bound[idx+1, dim, 1] = sig_  #TODO, get min std dev

                end
            end
        end
        @info "Calculated bounds for mode $mode in $mode_runtime seconds"
        # save data
        numpy.save(global_exp_dir*"/mean_data_$mode" * "_$refinement", mean_bound)
        numpy.save(global_exp_dir*"/sig_data_$mode" * "_$refinement", sig_bound)
        numpy.save(global_exp_dir*"/complete_$mode" * "_$refinement", 1)
    end

end