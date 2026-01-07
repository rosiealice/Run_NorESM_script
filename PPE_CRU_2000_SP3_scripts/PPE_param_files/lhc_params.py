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
basefile = paramsdir+"fates_params_sci.1.88.6_api.42.0.0_14pft_nor_sci1_api1_c251204.nc"
ctsm_basefile=paramsdir+"ctsm60_params.5.3.045_noresm_v14_c260107.nc"
outdir   = "lhs_params/"
nsamp    = 10  # number of ensemble members

# Parameter ranges (min, max)
param_ranges = {
    "fates_rad_leaf_clumping_index": (0.7, 1.10, 1),
    "fates_turb_leaf_diameter":  (0.5,  1.5 ,1),
    "fates_maintresp_leaf_atkin2017_baserate": (0.75,  1.25 ,1),
    "sucsat_sf":(0.9,1.10,0),
    "watsat_sf": (0.90,1.10 ,0)
}




# -----------------------------
# MAKE OUTPUT DIRECTORY
# -----------------------------
os.makedirs(outdir, exist_ok=True)


# -----------------------------
# BUILD LATIN HYPERCUBE
# -----------------------------
param_names = list(param_ranges.keys())
p_min = np.array([param_ranges[p][0] for p in param_names])
p_max = np.array([param_ranges[p][1] for p in param_names])

sampler = qmc.LatinHypercube(d=len(param_names))
unit_samples = sampler.random(n=nsamp)

# scale samples to physical ranges
samples = qmc.scale(unit_samples, p_min, p_max)

# Separate parameters by file type (1=fates, 0=ctsm)
fates_params = {p: i for i, p in enumerate(param_names) if param_ranges[p][2] == 1}
ctsm_params = {p: i for i, p in enumerate(param_names) if param_ranges[p][2] == 0}

# -----------------------------
# WRITE MODIFIED NETCDF FILES
# -----------------------------
for i in range(nsamp):
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    
    # --- Write FATES parameter file ---
    if fates_params:
        outfile = os.path.join(outdir, f"fates_params_lhs_{timestamp}_{i+1:03d}.nc")
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

            # --- overwrite the fates parameters ---
            for p, idx in fates_params.items():
                val = samples[i][idx]
                print(f"Writing {p} = {val:.4f} in {outfile}")
                dst.variables[p][:] = np.multiply(dst.variables[p][:], val)
    
    # --- Write CTSM parameter file ---
    if ctsm_params:
        ctsm_outfile = os.path.join(outdir, f"ctsm_params_lhs_{timestamp}_{i+1:03d}.nc")
        with Dataset(ctsm_basefile, 'r') as src, Dataset(ctsm_outfile, 'w') as dst:

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

            # --- overwrite the ctsm parameters ---
            for p, idx in ctsm_params.items():
                val = samples[i][idx]
                print(f"Writing {p} = {val:.4f} in {ctsm_outfile}")
                dst.variables[p][:] = np.multiply(dst.variables[p][:], val)
    
print("LHS parameter ensemble written to:", outdir)
