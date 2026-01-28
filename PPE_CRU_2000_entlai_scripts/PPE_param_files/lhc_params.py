import numpy as np
from scipy.stats import qmc
from netCDF4 import Dataset
import glob
import datetime
import os

# -----------------------------
# USER SETTINGS
# -----------------------------
paramsdir="/cluster/shared/noresm/inputdata/lnd/clm2/paramdata/"
basefile = paramsdir+"fates_params_sci.1.88.6_api.42.0.0_14pft_nor_sci4_api1_c260125.nc"
outdir   = "lhs_params/"
nsamp    = 9  # number of ensemble members

# Parameter ranges (min, max)
# For parameters that vary by PFT, you can specify:
#   - a single tuple (min, max) to apply the same range to all PFTs
#   - a dict {pft_index: (min, max)} to specify different ranges per PFT
#   - "all": (min, max) in the dict to set default for unspecified PFTs
# For scalar parameters, just use a single tuple (min, max)

param_ranges = {
   "fates_leaf_stomatal_slope_medlyn":{ 
        "all": (0.99,1.01),  # default for all PFTs
        13: (0.6, 1.1),        # specific range for PFT 1
        }, 
    "fates_allom_d2bl1": { 
        "all": (0.99,1.01),  # default for all PFTs
        1: (0.6, 1.1),        # specific range for PFT 1
        }, 
    "fates_allom_l2fr":  { 
        "all": (0.99,1.01),  # default for all PFTs
        1: (0.7, 1.5),        # specific range for PFT 1
        }, 
    "fates_leaf_vcmax25top": {  # PFT-specific ranges
        "all": (0.99,1.01),  # default for all PFTs
        5: (0.75, 1.25),        # specific range for PFT 1
        13: (0.75, 1.25),        # specific range for PFT 1
         },
    "fates_leaf_stomatal_intercept": {    
        "all": (0.99,1.01),  # default for all PFTs
        13: (0.2, 1.25),        # specific range for PFT 13
        }
    }

# -----------------------------
# MAKE OUTPUT DIRECTORY
# -----------------------------
os.makedirs(outdir, exist_ok=True)

# -----------------------------
# PROCESS PARAMETER RANGES
# -----------------------------
# Expand PFT-specific ranges into individual parameters for LHS sampling
expanded_params = {}

# First, get PFT dimensions from the base file
with Dataset(basefile, 'r') as src:
    for param_name, param_config in param_ranges.items():
        if param_name in src.variables:
            var = src.variables[param_name]
            
            # Check if parameter has a PFT dimension
            has_pft_dim = 'fates_pft' in var.dimensions
            
            if has_pft_dim and isinstance(param_config, dict):
                # PFT-specific ranges specified
                npft = var.shape[var.dimensions.index('fates_pft')]
                default_range = param_config.get("all", (0.75, 1.25))
                
                for pft_idx in range(npft):
                    pft_range = param_config.get(pft_idx, default_range)
                    expanded_params[f"{param_name}_pft{pft_idx}"] = {
                        'range': pft_range,
                        'base_param': param_name,
                        'pft_idx': pft_idx
                    }
            else:
                # Scalar parameter or same range for all PFTs
                if isinstance(param_config, dict):
                    param_range = param_config.get("all", (0.75, 1.25))
                else:
                    param_range = param_config
                
                expanded_params[param_name] = {
                    'range': param_range,
                    'base_param': param_name,
                    'pft_idx': None
                }


# -----------------------------
# BUILD LATIN HYPERCUBE
# -----------------------------
# Separate parameters into those that vary (for LHS) and those that are constant
varying_params = {}
constant_params = {}

for param_name, param_info in expanded_params.items():
    min_val, max_val = param_info['range']
    if min_val < max_val:
        varying_params[param_name] = param_info
    else:
        constant_params[param_name] = param_info

# Only sample varying parameters
if varying_params:
    varying_param_names = list(varying_params.keys())
    p_min = np.array([varying_params[p]['range'][0] for p in varying_param_names])
    p_max = np.array([varying_params[p]['range'][1] for p in varying_param_names])

    sampler = qmc.LatinHypercube(d=len(varying_param_names))
    unit_samples = sampler.random(n=nsamp)

    # scale samples to physical ranges
    varying_samples = qmc.scale(unit_samples, p_min, p_max)
else:
    varying_param_names = []
    varying_samples = np.zeros((nsamp, 0))

# -----------------------------
# WRITE MODIFIED NETCDF FILES
# -----------------------------
for i in range(nsamp):
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    outfile = os.path.join(outdir, f"fates_params_lhs_{timestamp}_{i+1:03d}.nc")

    # copy base file
    with Dataset(basefile, 'r') as src, Dataset(outfile, 'w') as dst:

        # --- copy global attributes ---
        dst.setncatts(src.__dict__)

        # --- copy dimensions ---
        for name, dim in src.dimensions.items():
            dst.createDimension(
                name,
                (len(dim) if not dim.isunlimited() else None)
            )

        # --- copy variables ---
        for name, var in src.variables.items():
            outvar = dst.createVariable(
                name, var.datatype, var.dimensions
            )
            outvar.setncatts(var.__dict__)
            outvar[:] = var[:]

        # --- overwrite the parameters ---
        # First apply varying parameters from LHS
        for p, val in zip(varying_param_names, varying_samples[i]):
            param_info = varying_params[p]
            base_param = param_info['base_param']
            pft_idx = param_info['pft_idx']
            
            if pft_idx is not None:
                # PFT-specific parameter - handle multidimensional arrays
                print(f"Writing {base_param}[pft={pft_idx}] = {val:.4f} in {outfile}")
                var = dst.variables[base_param]
                var_data = var[:]
                
                # Find which dimension is the PFT dimension
                pft_dim_idx = var.dimensions.index('fates_pft')
                
                # Build a slice tuple to access the specific PFT
                slices = [slice(None)] * len(var.dimensions)
                slices[pft_dim_idx] = pft_idx
                slices = tuple(slices)
                
                # Multiply the specific PFT slice
                var_data[slices] = np.multiply(var_data[slices], val)
                var[:] = var_data
            else:
                # Scalar parameter or apply to all PFTs
                print(f"Writing {base_param} = {val:.4f} in {outfile}")
                dst.variables[base_param][:] = np.multiply(dst.variables[base_param][:], val)
        
        # Then apply constant parameters (where min == max)
        for p, param_info in constant_params.items():
            base_param = param_info['base_param']
            pft_idx = param_info['pft_idx']
            val = param_info['range'][0]  # Use the constant value
            
            if pft_idx is not None:
                # PFT-specific parameter - handle multidimensional arrays
                print(f"Writing {base_param}[pft={pft_idx}] = {val:.4f} (constant) in {outfile}")
                var = dst.variables[base_param]
                var_data = var[:]
                
                # Find which dimension is the PFT dimension
                pft_dim_idx = var.dimensions.index('fates_pft')
                
                # Build a slice tuple to access the specific PFT
                slices = [slice(None)] * len(var.dimensions)
                slices[pft_dim_idx] = pft_idx
                slices = tuple(slices)
                
                # Multiply the specific PFT slice
                var_data[slices] = np.multiply(var_data[slices], val)
                var[:] = var_data
            else:
                # Scalar parameter or apply to all PFTs
                print(f"Writing {base_param} = {val:.4f} (constant) in {outfile}")
                dst.variables[base_param][:] = np.multiply(dst.variables[base_param][:], val)
    
print("LHS parameter ensemble written to:", outdir)
