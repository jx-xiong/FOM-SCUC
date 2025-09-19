push!(LOAD_PATH, joinpath(@__DIR__, ".", "src"))
using HPRUC

using JuMP
using JSON
using Gurobi
using HPRLP
using PyCall

import HPRUC:
    Formulation,
    KnuOstWat2018,
    MorLatRam2013,
    ShiftFactorsFormulation,
    Gar1962,
    CarArr2006,
    DamKucRajAta2016

import Base.Threads: @threads


function main()
    nthreads = 1
    println("Checking args")
    parsed = Dict{String,String}()
    i = 1
    while i <= length(ARGS)
        if startswith(ARGS[i], "-")
            # this one is an argument identifier
            key = ARGS[i][2:end]  # remove the leading "-"
            # check if the next one is value
            if i + 1 <= length(ARGS) && ~startswith(ARGS[i+1], "-")
                # Next is value, this one comes with value
                parsed[key] = ARGS[i+1]
                i += 2
            else
                # Next is not, this is a bool arg
                parsed[key] = "True"
                i += 1
            end
        else
            error("Unexpected argument format: $(ARGS[i])")
        end
    end

    # obtain all keys
    if haskey(parsed, "dataset")
        dataset_name = parsed["dataset"]
        @info "Setting dataset_name to $(dataset_name)"
    else
        dataset_name = "case14"
        # error("Missing critical arg: dataset")
    end

    if haskey(parsed, "threads")
        nthreads = parse(Int, parsed["threads"])
        @info "Setting nthreads to $(nthreads)"
    end

    if haskey(parsed, "subhour")
        subhour = true
        @info "Setting subhour to $(subhour)"
    else
        subhour = false
    end
    
    if haskey(parsed, "fom")
        use_fom = true
        @info "Using FOM: $(use_fom)"
    else
        use_fom = false
    end

    if haskey(parsed, "scale")
        scale = true
        @info "Setting scale to $(scale)"
    else
        scale = false
    end
    println("Finished loading args")


    date = "2017-11-04"

    ######################## run a simple instance for warm up 
    if use_fom
        @info "Warming up for FOM"
        fstt = "matpower/case14/" * date
        ori_is = HPRUC.read_benchmark(fstt, scale=scale)
        ori_model0 = HPRUC.build_model(
            instance=ori_is,
            optimizer=Gurobi.Optimizer,
            variable_names = true,
            formulation = Formulation(
                # pwl_costs = KnuOstWat2018.PwlCosts(),
                pwl_costs = Gar1962.PwlCosts(),
                ramping = DamKucRajAta2016.Ramping(),
            ),
            use_fom = use_fom,
        )
        ori_model0[:dataset_name] = "case14"

        JuMP.set_optimizer_attribute(ori_model0, "OutputFlag", 0)
        JuMP.set_optimizer_attribute(ori_model0, "Threads", 1)
        HPRUC.optimize!(ori_model0, HPRUC.HprTF.Method(time_limit=60.0,
                gap_limit=1e-3,
                two_phase_gap=true,
                ))
        println("Warm up done")
    end


    if subhour
        fstt = "matpower/$(dataset_name)/" * date
        ori_is = HPRUC.read_benchmark(fstt)
        run(`python /data1/jxxiong/hpr_uc.jl/instances/matpower_subhour/dataset_transformer.py --dataset $(dataset_name) --interpolate`, wait=true)
        fstt = "matpower_subhour/$(dataset_name)/" * date
        gap_limit = 1e-2
        two_phase_gap = false
    else
        fstt = "matpower/$(dataset_name)/" * date
        gap_limit = 1e-3
        two_phase_gap = true
    end
    ori_is = HPRUC.read_benchmark(fstt, scale=scale)

    return


    ########## constructing the model and solve using HPRUC.optimize!
    ori_model1 = HPRUC.build_model(
        instance=ori_is,
        optimizer=Gurobi.Optimizer,
        variable_names = true,
        formulation = Formulation(
            # pwl_costs = KnuOstWat2018.PwlCosts(),
            pwl_costs = Gar1962.PwlCosts(),
            ramping = DamKucRajAta2016.Ramping(),
        ),
        use_fom = use_fom,
    )
    ori_model1[:dataset_name] = dataset_name

    @info "Time window: $(ori_model1[:instance].time)"
    JuMP.set_optimizer_attribute(ori_model1, "OutputFlag", 1)
    JuMP.set_optimizer_attribute(ori_model1, "Threads", nthreads)
    println(ori_model1[:instance].time)

    total_time = @elapsed begin

        presolve_time, fom_time, milp_time, fixing_time, read_time, tf_time = HPRUC.optimize!(ori_model1, HPRUC.HprTF.Method(time_limit=3600.0,
                gap_limit=gap_limit,
                two_phase_gap=two_phase_gap,
                ))
    end

    constructive_obj = objective_value(ori_model1) * ori_model1[:instance].scenarios[1].obj_scale
    solution_starting = HPRUC.solution(ori_model1)
    sol_feas1 = HPRUC.validate(ori_is, solution_starting)

    
    printstyled("----------UC--------------\n")
    printstyled("  First obj: $(constructive_obj)\n"; color=:red)

    K = Threads.nthreads()
    if subhour
        filename = "framework_subhour_res.txt"
    else
        filename = "framework_res.txt"
    end
    open(filename,"a") do file
        println(file,"$(dataset_name) start $(constructive_obj) $(total_time-read_time) $(presolve_time) $(fom_time) $(milp_time) $(tf_time) feasible_$(sol_feas1)")
    end

    println("Total time: $(total_time-read_time) v.s. $(presolve_time + fom_time + milp_time + fixing_time + tf_time) seconds")
    println("Presolve time: $(presolve_time) seconds")
    println("FOM time: $(fom_time) seconds")
    println("MILP time: $(milp_time) seconds")
    println("Fixing time: $(fixing_time) seconds")
    println("TF time: $(tf_time) seconds")
end

main()