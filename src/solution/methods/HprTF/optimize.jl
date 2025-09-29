# HPRUC.jl: Optimization Package for Security-Constrained Unit Commitment
# Copyright (C) 2020, UChicago Argonne, LLC. All rights reserved.
# Released under the modified BSD license. See COPYING.md for more details.

using HPRLP
using PyCall
using Gurobi

function hpr_heuristic(
    model::JuMP.Model,
    # method::HprTF.Method,
    max_iter::Int = 3,
)::Tuple{Float64,Float64,Float64, Float64, Float64}
    read_time = 0.0
    fom_time = 0.0
    presolve_time = 0.0    
    fixing_time = 0.0
    tmp_read_time = 0.0

    instance = model[:instance]

    use_scale = model[:instance].scenarios[1].use_scale
    use_fom = model[:fom]

    params = HPRLP.HPRLP_parameters()
    params.time_limit = 3600
    params.max_iter = 100000
    params.stoptol = 1e-4
    params.device_number = 0
    params.use_gpu = true
    params.warm_up = false
    params.use_Ruiz_scaling = ~use_scale
    println("ruiz:", params.use_Ruiz_scaling)
    threshold = 0.1


    flag = true
    iter = 1

    t_ison = OrderedDict()
    t_switch_on = OrderedDict()
    t_switch_off = OrderedDict()
    fixed_values = OrderedDict()


    t_f_ison = OrderedDict()
    t_f_switch_on = OrderedDict()
    t_f_switch_off = OrderedDict()

    read_time += @elapsed begin
        write_to_file(model, "fixed.mps")
        # run(`python /data1/jxxiong/HPR-LP/scripts/presolve.py`, wait=true)
py"""
import gurobipy as gp
import time 
m = gp.read("fixed.mps")
m.setParam("Threads", 4)
m = m.relax()
start_time = time.time()
m = m.presolve()
presolve_time = time.time() - start_time
m.write("tmp.mps")
"""
    end

    read_time -= py"presolve_time"
    presolve_time += py"presolve_time"

    while flag
        # solve the relaxed model

        read_time += @elapsed begin
            model_relaxed = read_from_file("tmp.mps")
        end

        fom_time += @elapsed begin
            if use_fom
                result = HPRLP.run_single("tmp.mps", params)
                x = result.x
                tmp_read_time = result.read_time
            else
                tmp_read_time = @elapsed begin
                    tmp_model = read_from_file("tmp.mps")
                end
                set_optimizer(tmp_model, Gurobi.Optimizer)
                set_optimizer_attribute(tmp_model, "OutputFlag", 0)
                # set_optimizer_attribute(tmp_model, "Threads", 8)
                set_optimizer_attribute(tmp_model, "Crossover", 0)
                set_optimizer_attribute(tmp_model, "FeasibilityTol", 1e-4)
                set_optimizer_attribute(tmp_model, "OptimalityTol", 1e-4)
                set_optimizer_attribute(tmp_model, "BarConvTol", 1e-4)
                JuMP.optimize!(tmp_model)
                x = JuMP.value.(all_variables(tmp_model))
            end
        end

        fom_time -= tmp_read_time
        read_time += tmp_read_time

        read_time += @elapsed begin
            # tmp_model = read_from_file("tmp.mps")        
            variable_names = name.(all_variables(model_relaxed))
            var_dict = OrderedDict(zip(variable_names, 1:length(variable_names)))
        end


        # @info "solving time: $(solve_time(model_relaxed))"
        # @info "power time: $(result.power_time)"
        @info "ITER $(iter): Finished solving the relaxed model"
        iter += 1

        # check the solutions from of the relaxed model, is_on, switch_on, switch_off, startup, is_charging, is_discharging
        # @info "ITER $(iter): Finished getting the solution of the relaxed model"

        fixing_time += @elapsed begin
        for t in 1:instance.time
            for g in instance.scenarios[1].thermal_units

                is_on_g_t_name = name.(model[:is_on][g.name, t])
                # if is_on_g_t_name ∉ var_dict.keys
                if ! haskey(var_dict, is_on_g_t_name)
                    if haskey(fixed_values, is_on_g_t_name)
                        is_on_g_t = fixed_values[is_on_g_t_name]
                    else
                        is_on_g_t = 0.5
                    end
                else
                    is_on_g_t_idx = var_dict[is_on_g_t_name]
                    is_on_g_t = x[is_on_g_t_idx]
                end

                switch_on_g_t_name = name.(model[:switch_on][g.name, t])
                if ! haskey(var_dict, switch_on_g_t_name)
                    if haskey(fixed_values, switch_on_g_t_name)
                        switch_on_g_t = fixed_values[switch_on_g_t_name]
                    else
                        switch_on_g_t = 0.5
                    end
                else
                    switch_on_g_t_idx = var_dict[switch_on_g_t_name]
                    switch_on_g_t = x[switch_on_g_t_idx]
                end

                switch_off_g_t_name = name.(model[:switch_off][g.name, t])
                if ! haskey(var_dict, switch_off_g_t_name)
                    if haskey(fixed_values, switch_off_g_t_name)
                        switch_off_g_t = fixed_values[switch_off_g_t_name]
                    else
                        switch_off_g_t = 0.5
                    end
                else
                    switch_off_g_t_idx = var_dict[switch_off_g_t_name]
                    switch_off_g_t = x[switch_off_g_t_idx]
                end

                if is_on_g_t >= 1.0 - threshold
                    is_on_g_t = 1.0
                elseif is_on_g_t <= threshold
                    is_on_g_t = 0.0
                else
                    is_on_g_t = -1.0
                end

                if switch_on_g_t >= 1.0 - threshold
                    switch_on_g_t = 1.0
                elseif switch_on_g_t <= threshold
                    switch_on_g_t = 0.0
                else
                    switch_on_g_t = -1.0
                end
                
                if switch_off_g_t >= 1.0 - threshold
                    switch_off_g_t = 1.0
                elseif switch_off_g_t <= threshold
                    switch_off_g_t = 0.0
                else
                    switch_off_g_t = -1.0
                end
                t_ison[g.name, t] = is_on_g_t
                t_switch_on[g.name, t] = switch_on_g_t
                t_switch_off[g.name, t] = switch_off_g_t
                end
            end


        for g in instance.scenarios[1].thermal_units
            t_f_ison[g.name] = []
            t_f_switch_on[g.name] = []
            t_f_switch_off[g.name] = []
            # for t in model_relaxed[:instance].time:-1:2
            for t in 2:instance.time
                ison = t_ison[g.name, t]
                switch_on = t_switch_on[g.name, t]
                switch_off = t_switch_off[g.name, t]
                ison_prev = t_ison[g.name, t-1]

                if ison != -1.0 && switch_on != -1.0 && switch_off != -1.0 && ison_prev != -1.0 && ison - ison_prev == switch_on - switch_off && switch_off + switch_on <= 1.0
                    # t_f_ison[g.name] = push!(t_f_ison[g.name], [t, ison])
                    t_f_ison[g.name] = push!(t_f_ison[g.name], [t-1, ison_prev])
                    t_f_switch_on[g.name] = push!(t_f_switch_on[g.name], [t, switch_on])
                    t_f_switch_off[g.name] = push!(t_f_switch_off[g.name], [t, switch_off])
                else
                    # println("cannot propagate fixing for $(g.name)")
                    break
                end
            end
        end


        fixed_ison = 0
        fixed_switchon = 0
        fixed_switchoff = 0
        # for t in 1:model_relaxed[:instance].time
        for g in instance.scenarios[1].thermal_units
            for i in 1:length(t_f_ison[g.name])
                fixed_ison += 1
                JuMP.fix(model[:is_on][g.name, t_f_ison[g.name][i][1]], t_f_ison[g.name][i][2], force=true)
                fixed_values[name.(model[:is_on][g.name, t_f_ison[g.name][i][1]])] = t_f_ison[g.name][i][2]
            end
            for i in 1:length(t_f_switch_on[g.name])
                fixed_switchon += 1
                JuMP.fix(model[:switch_on][g.name, t_f_switch_on[g.name][i][1]], t_f_switch_on[g.name][i][2], force=true)
                fixed_values[name.(model[:switch_on][g.name, t_f_switch_on[g.name][i][1]])] = t_f_switch_on[g.name][i][2]
            end
            for i in 1:length(t_f_switch_off[g.name])
                fixed_switchoff += 1
                JuMP.fix(model[:switch_off][g.name, t_f_switch_off[g.name][i][1]], t_f_switch_off[g.name][i][2], force=true)
                fixed_values[name.(model[:switch_off][g.name, t_f_switch_off[g.name][i][1]])] = t_f_switch_off[g.name][i][2]
            end
        end
        end

        # write to file
        read_time += @elapsed begin
            write_to_file(model, "fixed.mps")
            # run(`python /data1/jxxiong/HPR-LP/scripts/presolve.py`, wait=true)
py"""
import gurobipy as gp
import time 
m = gp.read("fixed.mps")
m.setParam("Threads", 4)
start_time = time.time()
m  = m.presolve()
presolve_time = time.time() - start_time
m = m.relax()
m.write("tmp.mps")
"""
        end

        read_time -= py"presolve_time"
        presolve_time += py"presolve_time"

        @info "fixed ison: $(fixed_ison), switch_on: $(fixed_switchon), switch_off: $(fixed_switchoff)"
        if iter >= max_iter
            flag = false
        end
    end
    @info "solving the fixed model"
    JuMP.optimize!(model)
    milp_time = solve_time(model)
    # return t_f_ison, t_f_switch_on, t_f_switch_off, read_time
    return presolve_time, fom_time, milp_time, fixing_time, read_time
end


function optimize!(model::JuMP.Model, method::HprTF.Method)::Tuple{Float64,Float64,Float64, Float64, Float64, Float64}
    if !occursin("Gurobi", JuMP.solver_name(model))
        method.two_phase_gap = false
    end
    function set_gap(gap)
        JuMP.set_optimizer_attribute(model, "MIPGap", gap)
        @info @sprintf("MIP gap tolerance set to %f", gap)
    end
    initial_time = time()
    large_gap = false
    max_iter = 3
    has_transmission = false
    for sc in model[:instance].scenarios
        if length(sc.isf) > 0
            has_transmission = true
        end
        if has_transmission && method.two_phase_gap
            set_gap(1e-2)
            max_iter = 3
            large_gap = true
        else
            set_gap(method.gap_limit)
            max_iter = 3
            large_gap = false
        end
    end
    presolve_time_total = 0.0
    fom_time_total = 0.0
    milp_time_total = 0.0
    fixing_time_total = 0.0
    read_time_total = 0.0
    tf_time_total = 0.0
    while true
        time_elapsed = time() - initial_time
        time_remaining = method.time_limit - time_elapsed
        if time_remaining < 0
            @info "Time limit exceeded"
            break
        end
        @info @sprintf(
            "Setting MILP time limit to %.2f seconds",
            time_remaining
        )
        JuMP.set_time_limit_sec(model, time_remaining + read_time_total)
        @info "Solving MILP..."
        # JuMP.optimize!(model) # replacing this with the hpr heuristic
        presolve_time, fom_time, milp_time, fixing_time, read_time = HPRUC.hpr_heuristic(model, max_iter)
        read_time_total += read_time
        presolve_time_total += presolve_time
        fom_time_total += fom_time
        milp_time_total += milp_time
        fixing_time_total += fixing_time

        has_transmission || break

        @info "Verifying transmission limits..."

        tf_time_total += @elapsed begin
        time_screening = @elapsed begin
            violations = []
            for sc in model[:instance].scenarios
                push!(
                    violations,
                    _find_violations(
                        model,
                        sc,
                        max_per_line = method.max_violations_per_line,
                        max_per_period = method.max_violations_per_period,
                    ),
                )
            end
        end
        @info @sprintf(
            "Verified transmission limits in %.2f seconds",
            time_screening
        )

        violations_found = false
        for v in violations
            if !isempty(v)
                violations_found = true
            end
        end
        end

        if violations_found
            tf_time_total += @elapsed begin
            for (i, v) in enumerate(violations)
                _enforce_transmission(model, v, model[:instance].scenarios[i])
            end
            end
        else
            @info "No violations found"
            if large_gap
                large_gap = false
                set_gap(method.gap_limit)
                max_iter = 5

                if true
                    milp_time_total += @elapsed begin
                        JuMP.optimize!(model)
                    end

                    tf_time_total += @elapsed begin
                        @info "Verifying transmission limits..."
                        time_screening = @elapsed begin
                            violations = []
                            for sc in model[:instance].scenarios
                                push!(
                                    violations,
                                    _find_violations(
                                        model,
                                        sc,
                                        max_per_line = method.max_violations_per_line,
                                        max_per_period = method.max_violations_per_period,
                                    ),
                                )
                            end
                        end
                        @info @sprintf(
                            "Verified transmission limits in %.2f seconds",
                            time_screening
                        )
                    
                        violations_found = false
                        for v in violations
                            if !isempty(v)
                                violations_found = true
                            end
                        end
                    end
                
                    if violations_found
                        tf_time_total += @elapsed begin
                            for (i, v) in enumerate(violations)
                                _enforce_transmission(model, v, model[:instance].scenarios[i])
                            end
                        end
                    else
                        @info "No violations found"
                        break
                    end
                end
            else
                break
            end
        end


        fixing_time_total += @elapsed begin
        for g in model[:instance].scenarios[1].thermal_units
            for t in 1:model[:instance].time
                if is_fixed(model[:is_on][g.name, t])
                    JuMP.unfix(model[:is_on][g.name, t])
                end
                if is_fixed(model[:switch_on][g.name, t])
                    JuMP.unfix(model[:switch_on][g.name, t])
                end
                if is_fixed(model[:switch_off][g.name, t])
                    JuMP.unfix(model[:switch_off][g.name, t])
                end
            end
        end
        end

    end
    return presolve_time_total, fom_time_total, milp_time_total, fixing_time_total, read_time_total, tf_time_total
end
