timestamp=$(date +"%Y-%m-%d %H:%M:%S")
echo "==========Running script on instance: $timestamp; gurobi, noscale==========" >> framework_res.txt
for instance in $(cat instances.txt); do
    julia --threads=8 --project="../HPR-LP" test.jl -dataset $instance -threads 8 2>&1 | tee ./logs/gurobi/${instance}.log;
done

timestamp=$(date +"%Y-%m-%d %H:%M:%S")
echo "==========Running script on instance: $timestamp; float64, noscale==========" >> framework_res.txt
for instance in $(cat instances.txt); do
    julia --threads=8 --project="../HPR-LP" test.jl -dataset $instance -threads 8 -fom 2>&1 | tee ./logs/float64_noscale/${instance}.log;
done

timestamp=$(date +"%Y-%m-%d %H:%M:%S")
echo "==========Running script on instance: $timestamp; uc==========" >> uc_res.txt
for instance in $(cat instances.txt); do
    julia --threads=8 --project="../HPR-LP" test_uc.jl -dataset $instance -threads 8 2>&1 | tee ./logs/uc/${instance}.log;
done

timestamp=$(date +"%Y-%m-%d %H:%M:%S")
echo "==========Running script on instance: $timestamp; td==========" >> td_res.txt
for instance in $(cat instances.txt); do
    julia --threads=8 --project="../HPR-LP" test_td.jl -dataset $instance -threads 8 2>&1 | tee ./logs/td/${instance}.log;
done

## mannually set the precision for GPU in the FOM LP Solver before running the following script
timestamp=$(date +"%Y-%m-%d %H:%M:%S")
echo "==========Running script on instance: $timestamp; float32, scale==========" >> framework_res.txt
for instance in $(cat instances.txt); do
    julia --threads=8 --project="../HPR-LP" test.jl -dataset $instance -threads 8 -scale -fom 2>&1 | tee ./logs/float32/${instance}.log;
done

timestamp=$(date +"%Y-%m-%d %H:%M:%S")
echo "==========Running script on instance: $timestamp; float32, noscale==========" >> framework_res.txt
for instance in $(cat instances.txt); do
    julia --threads=8 --project="../HPR-LP" test.jl -dataset $instance -threads 8 -fom 2>&1 | tee ./logs/float32_noscale/${instance}.log;
done
