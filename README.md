# FOM SF for SCUC
This repo is mainly developed as an extension of the UnitCommitment.jl [1],[2]

## Setup
- HPR-LP [3] solver with single-precision (modified and forked from the original repo [4]): https://github.com/jx-xiong/HPR-LP.git
Folder structure:
```
- FOM-SCUC # current directory
- HPR-LP
```
- Python: 
```
conda env create -f environment.yml
```
- Julia dependencies
```
julia --project="../HPR-LP"
ENV["PYTHON"] = "xxxxx"
]
instantiate
build PyCall
```

## Parameters
main function `test.jl` with abaliation methods by setting the following parameters
- `-fom`: use first-order method LP solvers, otherwise, use Gurobi
- `-scale`: use instance-aware scaling instead of the defualt ruiz scaling

To run with `-fom` under single-precision, mannually update the parameter in `../HPR-LP/src/HPRLP.jl`.

## Run
```
bash scripts.sh
```

## Citations
[1] A. S. Xavier, A. M. Kazachkov, O. Yurdakul, and F. Qiu, “Unitcommit-
ment. jl: A julia/jump optimization package for security-constrained unit
commitment (version 0.3),” JuMP Optimization Package for Security-
Constrained Unit Commitment (Version 0.3), Zenodo, 2022.

[2] https://github.com/ANL-CEEESA/UnitCommitment.jl.git

[3] K. Chen, D. Sun, Y. Yuan, G. Zhang, and X. Zhao, “Hpr-lp: An
implementation of an hpr method for solving linear programming,” arXiv
preprint arXiv:2408.12179, 2024.

[4] https://github.com/PolyU-IOR/HPR-LP.git
