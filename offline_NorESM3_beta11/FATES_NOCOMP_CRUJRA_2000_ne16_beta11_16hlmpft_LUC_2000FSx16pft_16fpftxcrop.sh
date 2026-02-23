#!/bin/bash 

#Scrip to clone, build and run NorESM on Betzy

dosetup1=1 #do first part of setup
dosetup2=1 #do second part of setup (after first manual modifications)
dosetup3=1 #do second part of setup (after namelist manual modifications)
dosubmit=1 #do the submission stage
forcenewcase=1 #scurb all the old cases and start again
doanalysis=0 #analyze output (not yet coded up)
numCPUs=0 #Specify number of cpus. 0: use default

echo "setup1, setup2, setup3, submit, forcenewcase, analysis:", $dosetup1, $dosetup2, $dosetup3, $dosubmit, $forcenewcase, $doanalysis 

USER="rosief"
project='nn9560k' #nn8057k: EMERALD, nn2806k: METOS, nn9188k: CICERO, nn9560k: NorESM (INES2), nn9039k: NorESM (UiB: Climate predition unit?), nn2345k: NorESM (EU projects)
machine='betzy'

#NorESM dir
noresmrepo="noresm3_0_beta_11"
noresmversion="noresm3_0_beta11"


resolution="ne16pg3_tn14" #f19_g17, ne30pg3_tn14, f45_f45_mg37, ne16pg3_tn14 
casename="i2000.$resolution.fatesnocomp.$noresmversion.CRUJRA.16hlmpft_LUC_2000FSx16pft_16fpftxcrop.`date +"%Y-%m-%d"`"
echo "casename: $casename"
compset="2000_DATM%CRUJRA2024_CLM60%FATES_SICE_SOCN_SROF_SGLC_SWAV_SESP"


# aka where do you want the code?
workpath="/cluster/work/users/$USER/" 

# some more derived path names to simplify scripts
scriptsdir=$workpath$noresmrepo/cime/scripts/

#case dir
casedir=$scriptsdir$casename

#where are we now?
startdr=$(pwd)

#Download code and checkout externals
if [ $dosetup1 -eq 1 ] 
then
    cd $workpath

    pwd
    #go to repo, or checkout code
    if [[ -d "$noresmrepo" ]] 
    then
        cd $noresmrepo
        echo "Already have NorESM repo"
    else
        echo "Cloning NorESM"
        
        if [[ $noresmversion == ctsm* ]] ; then
            echo "Using CTSM version $noresmversion"
            git clone https://github.com/NorESMhub/CTSM/ $noresmrepo
        else
            echo "Using NorESM version $noresmversion"
            git clone https://github.com/NorESMhub/NorESM/ $noresmrepo
        fi
        cd $noresmrepo
        git checkout $noresmversion
        ./bin/git-fleximod update
        echo "Built model here: $workpath$noresmrepo"        
	
    fi
fi

#Make case
if [[ $dosetup2 -eq 1 ]] 
then
    cd $scriptsdir

    if [[ $forcenewcase -eq 1 ]]
    then
	echo "making a new case"
        if [[ -d "$casedir" ]] 
        then    
        echo "$casedir exists on your filesystem. Removing it!"
        rm -rf $casedir
        rm -r $casedir
        rm -r $workpath/archive/$casename
        rm -r $casename
        fi
    fi
    if [[ -d "$scriptsdir" ]] 
    then    
        echo "scriptsdir:" $scriptsdir
	cd $scriptsdir
        ./create_newcase --case $casedir --compset $compset --res $resolution --project $project --run-unsupported --mach betzy --pecount L
        cd $casename
        echo "created new case"
#        cp /cluster/home/kjetisaa/Trendy_2025_scripts/SourceModFiles_S3rerun/BalanceCheckMod.F90 $workpath$casename/SourceMods/src.clm/

        #XML changes
        echo 'updating settings'        
        ./xmlchange RUN_STARTDATE=0000-01-01
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=6
        ./xmlchange RESUBMIT=4
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=03:00:00
        ./xmlchange --subgroup case.st_archive JOB_WALLCLOCK_TIME=00:30:00        
        ./xmlchange DATM_YR_ALIGN=1
        ./xmlchange RUN_STARTDATE=0001-01-01        
        echo 'done with xmlchanges'        
        
        ./case.setup
        echo ' '
        echo "Done with Setup. Update namelists in $workpath$casename/user_nl_*"

        #Add following lines to user_nl_clm    
        echo "glacier_region_behavior = 'single_at_atm_topo','UNSET','virtual','virtual'" >> $workpath$casename/user_nl_clm
	echo " use_fates_nocomp = .true." >> $casedir/user_nl_clm
 	echo " use_fates_fixed_biogeog = .true." >> $casedir/user_nl_clm

        echo " fsurdat='/cluster/shared/noresm/inputdata/lnd/clm2/surfdata_esmf/ctsm5.4.0/surfdata_ne16np4.pg3_hist_2000_16pfts_c260209.nc' " >> $casedir/user_nl_clm      
        echo " fates_paramfile ='/cluster/work/users/rosief/paramscratch/fates_params_sci.1.88.6_api.42.0.0_14pft_nor_sci2_api1_c260206_16hlmpft_crops.nc'" >> $casedir/user_nl_clm

 #Land use changes 
        echo "use_fates_luh = .true."  >> $casedir/user_nl_clm
        echo "use_fates_lupft = .true."  >> $casedir/user_nl_clm
        echo "fates_harvest_mode = 'luhdata_area'"  >> $casedir/user_nl_clm
        echo "use_fates_potentialveg = .false."  >> $casedir/user_nl_clm
        echo "fluh_timeseries='/cluster/shared/noresm/inputdata/LU_data_CMIP7/LUH3_states_transitions_management.timeseries_ne16_hist_steadystate_1850_2026-02-09_cdf5.nc'"  >> $casedir/user_nl_clm
        echo "flandusepftdat='/cluster/shared/noresm/inputdata/LU_data_CMIP7/fates_landuse_pft_map_to_surfdata_ne16np4_260209_cdf5.nc'"  >> $casedir/user_nl_clm
    fi
fi

#Build case case
if [[ $dosetup3 -eq 1 ]] 
then
    cd $casedir
    echo "casedir", $casedir
    echo "Currently in" $(pwd)
    ./case.build
    echo ' '    
    echo "Done with Build"
fi

#Submit job
if [[ $dosubmit -eq 1 ]] 
then
    cd $casedir
    ./case.submit
    echo " "
    echo 'done submitting'       
fi

