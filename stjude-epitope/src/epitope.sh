#!/bin/bash
# epitope 0.0.1
# Generated by dx-app-wizard.
#
# Basic execution pattern: Your app will run on a single machine from
# beginning to end.
#
# Your job's input variables (if any) will be loaded as environment
# variables before this script runs.  Any array inputs will be loaded
# as bash arrays.
#
# Any code outside of main() (or any entry point you may add) is
# ALWAYS executed, followed by running the entry point itself.
#
# See https://wiki.dnanexus.com/Developer-Portal for tutorials on how
# to modify this file.

main() {

    echo "SNV or fusion?: '$SNV_or_fusion'"
    #echo "Mutation_file: '$mutation_file'"
    #echo "HLA allele: '$hla_allele'"
    echo "Mer size: '$Peptide_size'"
    echo "Affinity threshold: '$Affinity_threshold'"

    # The following line(s) use the dx command-line tool to download your file
    # inputs to the local file system using variable names for the filenames. To
    # recover the original filenames, you can use the output of "dx describe
    # "$variable" --name".
    if [ $Peptide_size -gt 15 ] || [ $Peptide_size -lt 8 ]; then
	echo -e "[error] Peptide size has to be between 8 and 15 ... exiting"
	exit 1
    fi

    mkdir -p mutation
    for i in "${!mutation_file[@]}"; do
        dx download "${mutation_file[$i]}" -f -o mutation
    done
    mkdir -p hla
    dx download "$hla_allele" -o hla


    # Fill in your application code here.
    echo -e "[pre] build HLA alleles array for samples ... `date`"
    hla_file=$( ls hla/* )
    if [ -s $hla_file ]; then
	declare -A HLA_ary
	function join_by { local IFS="$1"; shift; echo "$*"; }
	idx=0
        while IFS=$'\t' read -r -a line_ary; do
                patient="${line_ary[0]}"
		HLA=$( join_by ',' "${line_ary[@]:1}")
		#echo -e "$patient\t$HLA"
                HLA_ary+=([$patient]=$HLA)
		idx=$(( idx + 1 ))
        done < $hla_file
        echo -e "HLA number: ${#HLA_ary[@]}"
	
	### print HLA array
	#for i in "${!HLA_ary[@]}"; do
  	#	echo "sample  : $i"
  	#	echo "HLA     : ${HLA_ary[$i]}"
	#done
	
    else
	echo -e "[...error] HLA file not found"
    fi

    ### get refernece genome from DNAnexus
    echo -e "[genome] ... `date`"
    mkdir -p genome
    #dx download file-B6qq93v2J35fB53gZ5G0007K -o genome/hg19.fa.gz
    #dx download file-ByGVY5j04Y0xPfZZfQ0Y85p6 -o genome/hg19.fa.fai 
    mv /usr/genome/hg19.fa.gz genome/.
    mv /usr/genome/hg19.fa.fai genome/.
    gunzip genome/hg19.fa.gz

    ls -l genome
    #echo -e "[Current path]"
    #pwd

    ### set up environment ###
    echo "[HTML env] ... `date`"
	#ls -l /usr/HTML.py/
        current_d=$(pwd)
        pip install xlsxwriter
        cd '/usr/HTML.py/'
	python setup.py install
        cd $current_d
    echo "[HTML set up] ... `date`"
    
    echo "[Env env] ... `date`"
    sudo apt-get update
    sudo apt-get install -y tcsh lzma liblzma-dev
    pip install numpy --upgrade
    pip install pandas
    pip install cython
    pip install pysam
    pip install biopython
    pip install pyliftover
    echo "[Env set done] ... `date`"
    ##########################

    ### set up variables   ###
    net="$(ls /usr/bin/netMHCcons*/netMHCcons)" 
    snv_exe="/usr/bin/SNV_epitope.py"
    fusion_exe="/usr/bin/fusion_epitope.py"
    net_py="/usr/bin/netmhccons.py"
    report_py="/usr/bin/table2html.py"
    mer=$Peptide_size
    ##########################

    ### main code section  ###

    echo -e "[main run] ... `date`"
    if [ $SNV_or_fusion == "SNV" ]; then
    	for mut in $HOME/mutation/*; do
		sample=$( basename $mut )
		sample=${sample%%.*}
		echo -e "[...sample] $sample ... `date`"
		if test "${HLA_ary[$sample]+find}"; then
			allele=${HLA_ary[$sample]}
			#echo -e "...allele for test: ${allele}"
    			python $snv_exe -i $mut -o $sample.snv.affinity.out -n $net -s $mer -a "${allele}" -rO $sample.affinity.snv.expression.out -log $sample.epitope.log
		else
			echo -e "[...error] $sample not found in the HLA allele table"
		fi
    	done
    elif [ $SNV_or_fusion == "fusion" ]; then
	echo -e "[...extract fusion flanking peptide] ... `date`"
	for mut in $HOME/mutation/*; do
		ls -l $HOME/mutation
		python $fusion_exe -f $mut -s $mer
	done
	ls -l
	echo -e "[...run affinity prediction] ... `date`"
	for fus in *.seq; do
		echo $fus
		sample=$( basename $fus )
                sample=${sample%%.*}
		if test "${HLA_ary[$sample]+find}"; then
			allele=${HLA_ary[$sample]}
			#echo -e "...allele for test: ${allele}"
			python $net_py -i $fus -o $sample.fusion.affinity.out -n $net -s $mer -a "${allele}"
		else
			echo -e "[...error] $sample not found"
		fi
	done
    else
	echo -e "[error] unknown mutation file type: $SNV_or_fusion"
    fi
    

    ##########################

    # To report any recognized errors in the correct format in
    # $HOME/job_error.json and exit this script, you can use the
    # dx-jobutil-report-error utility as follows:
    #
    #   dx-jobutil-report-error "My error message"
    #
    # Note however that this entire bash script is executed with -e
    # when running in the cloud, so any line which returns a nonzero
    # exit code will prematurely exit the script; if no error was
    # reported in the job_error.json file, then the failure reason
    # will be AppInternalError with a generic error message.

    # The following line(s) use the utility dx-jobutil-add-output to format and
    # add output variables to your job's output as appropriate for the output
    # class.  Run "dx-jobutil-add-output -h" for more information on what it
    # does.

    #ls -l
	
    echo -e "[reformat results] `date`"
    outfolder="out/epitope/results"
    outfolder_raw="out/epitope/results/raw_output"
    mkdir -p $outfolder
    mkdir -p $outfolder_raw
    
    ### reformat output to html and xlsx
    #ls -l
    python $report_py -e '.affinity.out' -p './' -c $Affinity_threshold
    
    ### move outputs
    echo -e "[upload results] `date`"
    mv *.affinity.out $outfolder_raw
    mv *.html $outfolder
    #mv html $outfolder
    mv xlsx $outfolder
    mv *.seq $outfolder_raw
    #ls -l $outfolder
    
    output=$(dx upload $outfolder --recursive --brief)

    dx-upload-all-outputs

    #for i in "${!output[@]}"; do
    #    dx-jobutil-add-output output "${output[$i]}" --class=array:file
    #done
}
