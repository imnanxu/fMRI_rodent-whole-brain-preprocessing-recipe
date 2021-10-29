##########################################################################
##########################    Parameters    ##############################
##########################################################################
model="rat"
# model="mouse"
Foldername=(data_"$model"1) # Foldername=(data_mouse) #If you have group data, this can be extended to ...
# Foldername=(data_"$model"1 data_"$model"2 data_"$model"3 data_"$model"4)
bet_f=0.55 # You might need to play with this parameter for creating the tightest brain mask to save you some time of manual editing.
# NeedSTC=0; 
NeedSTC=1;
matlab_dir="/mnt/c/Program Files/MATLAB/R2018b/bin/matlab.exe"; 

##########################################################################
##########################     Program      ##############################
##########################################################################
for (( i=0; i<${#Foldername[@]}; i++ ))
do
	workingdir="${Foldername[i]}"

	# ##-------------Slice time correction-------- 
	echo "====================$workingdir: Slice time correction===================="
	if [[ $NeedSTC -eq 1 ]]
	then
		echo "Long TR, need STC"
		slicetimer -i ./"$workingdir"/EPI0  -o ./"$workingdir"/EPI.nii.gz  -r 2 -v	
		slicetimer -i ./"$workingdir"/EPI_reverse0  -o ./"$workingdir"/EPI_reverse.nii.gz  -r 2 -v	
		slicetimer -i ./"$workingdir"/EPI_forward0  -o ./"$workingdir"/EPI_forward.nii.gz  -r 2 -v	
	else
		echo "Short TR, do not need STC"
		fslchfiletype NIFTI_GZ ./"$workingdir"/EPI0 ./"$workingdir"/EPI.nii.gz
		fslchfiletype NIFTI_GZ ./"$workingdir"/EPI_reverse0 ./"$workingdir"/EPI_reverse.nii.gz
		fslchfiletype NIFTI_GZ ./"$workingdir"/EPI_forward0 ./"$workingdir"/EPI_forward.nii.gz
	fi

	# ##-------------Motion correction-------- 
	echo "====================$workingdir: Motion correction===================="
	fslmaths ./"$workingdir"/EPI.nii.gz -Tmean ./"$workingdir"/EPI_mean.nii.gz
	mcflirt -in ./"$workingdir"/EPI.nii.gz -reffile ./"$workingdir"/EPI_mean.nii.gz -out ./"$workingdir"/EPI_mc -stats -plots -report -rmsrel -rmsabs -mats	

	echo "--------------------$workingdir: Motion correction QC--------------------"	
	mkdir -p ./"$workingdir"/mc_qc/
	fsl_tsplot -i ./"$workingdir"/EPI_mc.par -t 'MCFLIRT rotations (radians)' -u 1 --start=1 --finish=3 -a x,y,z -w 640 -h 144 -o  ./"$workingdir"/mc_qc/EPI_mc_rot.png
	fsl_tsplot -i ./"$workingdir"/EPI_mc.par -t 'MCFLIRT estimated translations (mm)' -u 1 --start=4 --finish=6 -a x,y,z -w 640 -h 144 -o ./"$workingdir"/mc_qc/EPI_mc_trans.png
	fsl_tsplot -i ./"$workingdir"/EPI_mc_rel.rms,./"$workingdir"/EPI_mc_abs.rms -t 'MCFLIRT estimated mean displacement (mm)' -u 1 -w 640 -h 144 -a absolute,relative -o ./"$workingdir"/mc_qc/EPI_mc_disp.png

	## Calculate temporal SNR (tSNR):
	fslmaths ./"$workingdir"/EPI_mc -Tstd ./"$workingdir"/mc_qc/EPI_mc_std
	fslmaths ./"$workingdir"/EPI_mc -Tmean ./"$workingdir"/mc_qc/EPI_mc_mean
	fslmaths ./"$workingdir"/mc_qc/EPI_mc_mean.nii.gz -div ./"$workingdir"/mc_qc/EPI_mc_std.nii.gz  ./"$workingdir"/mc_qc/EPI_mc_tSNR.nii.gz
	fslmaths ./"$workingdir"/mc_qc/EPI_mc_mean.nii.gz -thrp 15 -bin ./"$workingdir"/mc_qc/EPI_snr_mask.nii.gz
	fslstats -K ./"$workingdir"/mc_qc/EPI_snr_mask.nii.gz ./"$workingdir"/mc_qc/EPI_mc_tSNR.nii.gz -n -m > ./"$workingdir"/mc_qc/EPI_mean_tSNR.txt	
	rm ./"$workingdir"/mc_qc/EPI_snr_mask.nii.gz
	rm ./"$workingdir"/mc_qc/EPI_mc_std.nii.gz
	rm ./"$workingdir"/mc_qc/EPI_mc_mean.nii.gz
	
	##-------------Topup correction-------- 
	echo "====================$workingdir: Topup correction===================="
	# fslroi ./"$workingdir"/EPI.nii ./"$workingdir"/EPI_forward 0 1
	mcflirt -in ./"$workingdir"/EPI_forward -r ./"$workingdir"/EPI_mean.nii.gz -out ./"$workingdir"/EPI_forward -stats -plots -report -rmsrel -rmsabs -mats
	applyxfm4D ./"$workingdir"/EPI_reverse ./"$workingdir"/EPI_forward ./"$workingdir"/EPI_reverse ./"$workingdir"/EPI_forward.mat -fourdigit
	fslmerge -t ./"$workingdir"/rpEPI ./"$workingdir"/EPI_forward ./"$workingdir"/EPI_reverse
	fslchfiletype NIFTI_GZ ./"$workingdir"/rpEPI ./"$workingdir"/rpEPI_mc
	# mcflirt -in ./"$workingdir"/rpEPI -refvol 0 -out ./"$workingdir"/rpEPI_mc -stats -plots -report -rmsrel -rmsabs -mats	
	# topup --imain=./"$workingdir"/rpEPI_mc --config=./lib/topup/b02b0.cnf \
	# 	--datain=./lib/topup/datain_topup.txt --out=./"$workingdir"/tu_g --iout=./"$workingdir"/tus_g -v
	topup --imain=./"$workingdir"/rpEPI_mc --config=./lib/topup/"$model"EPI_topup.cnf \
		--datain=./lib/topup/"$model"datain_topup.txt --out=./"$workingdir"/tu_g --iout=./"$workingdir"/tus_g -v
	applytopup --imain=./"$workingdir"/EPI_mc --inindex=1 --datain=./lib/topup/"$model"datain_topup.txt \
		--topup=./"$workingdir"/tu_g --method=jac --out=./"$workingdir"/EPI_g
	fslmaths ./"$workingdir"/EPI_g -abs ./"$workingdir"/EPI_topup
	fslmaths ./"$workingdir"/EPI_topup -Tmean ./"$workingdir"/EPI_topup_mean

	##-------------Brain extraction-------- 
	echo "====================$workingdir: Brain extraction===================="
	N4BiasFieldCorrection -d 3 -i ./"$workingdir"/EPI_topup_mean.nii.gz -o ./"$workingdir"/EPI_n4.nii.gz -c [100x100x100,0] -b [50] -s 2
	if [ "$model" = "mouse" ]; then
		echo "--------------------$workingdir: CSF regions estimation for mouse--------------------"	
		fslmaths ./"$workingdir"/EPI_n4.nii.gz -thrp 99 -bin ./"$workingdir"/EPI_csf_mask1pass
		fslmaths ./"$workingdir"/EPI_n4.nii.gz -mas ./"$workingdir"/EPI_csf_mask1pass ./"$workingdir"/EPI_csf_masked1pass
		fslmaths ./"$workingdir"/EPI_csf_masked1pass -thrP 90 -bin ./"${workingdir}"/EPI_n4_csf_mask0.nii.gz	
		rm ./"$workingdir"/EPI_csf_masked1pass.nii.gz
		rm ./"$workingdir"/EPI_csf_mask1pass.nii.gz
	fi
	
	echo "--------------------$workingdir: brain mask FSL bet--------------------"	
	bet ./"$workingdir"/EPI_n4.nii.gz ./"$workingdir"/EPI_n4_bet.nii.gz -f $bet_f -g 0 -R
	fslmaths ./"$workingdir"/EPI_n4_bet.nii.gz -bin ./"$workingdir"/EPI_n4_bet_mask.nii.gz
	# PCNN3d brain extraction. One can also run the file in Matlab.
	echo "--------------------$workingdir: brain mask PCNN3D--------------------"	
	"$matlab_dir" -nodesktop -r "addpath(genpath('./PCNN3D_matlab')); datpath='./$workingdir/EPI_n4.nii.gz'; run PCNN3D_run_v1_3.m; exit"	
 	
	## Then, manually edit the mask slice by slice in fsleyes
done
