#!/bin/bash 


module load NRIS/CPU
module load Python/3.12.3-GCCcore-13.3.0

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
machine='olivia'

#NorESM dir
noresmrepo="noresm3_0_beta_12fireemis_may26_branch"
noresmversion="noresm3_0_beta12"


resolution="f45_f45_mg37" #f19_g17, ne30pg3_tn14, f45_f45_mg37, ne16pg3_tn14 

casename="i1850_$noresmversion.CRUJRA.fireemis_branch.`date +"%Y-%m-%d"`"
echo "casename: $casename"
compset="1850_DATM%CRUJRA2024_CLM60%FATES_SICE_SOCN_SROF_SGLC_SWAV_SESP"


# aka where do you want the code?
workpath="/cluster/work/projects/nn9560k/$USER/" 

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

	cd components/clm/src/
	git remote add rosiectsm https://github.com/rosiealice/ctsm
	git fetch rosiectsm
	git switch --track rosiectsm/fire_emissions_may26
        cd fates 
        git remote add rosiefates https://github.com/rosiealice/fates
        git fetch rosiefates
        git switch --track rosiefates/fix-fates-fire-emissions
	
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
        ./create_newcase --case $casedir --compset $compset --res $resolution --project $project --run-unsupported --mach $machine  --pecount L
        cd $casename
        echo "created new case"


        #XML changes
        echo 'updating settings'        
        ./xmlchange RUN_STARTDATE=0000-01-01
        ./xmlchange STOP_OPTION=nyears
        ./xmlchange STOP_N=2
        ./xmlchange RESUBMIT=0
        ./xmlchange --subgroup case.run JOB_WALLCLOCK_TIME=01:00:00
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

