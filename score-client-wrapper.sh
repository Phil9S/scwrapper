#!/bin/bash

## score-client-wrapper.sh - Smith, PS - Markowetz Lab, CRUK CI
## version 1 - Release 19/02/2020

## Variables

# Assigned
ROOT_DIR="NULL"
TOKEN="NULL"
PROFILE="collab"
MANIFEST="NULL"
BATCH="NONE"
BATCH_NUMBER="1"
BATCH_SCRIPT=""

#Fixed-imperm
MANIFEST_FIELDS=11
ID_PATTERN="^[\w]{8}-[\w]{4}-[\w]{4}-[\w]{4}-[\w]{12}$"
TEMP="TRUE"
FORCE="FALSE"
KEEP="FALSE"
SUM_DIR="$HOME/"
SUM_NAME="file_summary.txt"

# Fixed-perm
DATE=$(date "+%Y_%m_%d_%H%M%S")
ECHO=$(echo "[score-client-wrapper]")
PWD=$(pwd)
INTEGER_CHECK="^[1-9]$|^[1-9][0-9]+$"
FLOAT_CHECK="^[0][.][0-9]+$|^[1][.][0]$"
SIZE_PATTERN="^(\d*\.?\d+)(?(?=[KMGT])([KMGT])(?:i?B)?|B?)$"
MIN_BATCH_SIZE=1000000000

## Default behaviour
if [[ $# -eq 0 ]]; then
	echo -e "\n${ECHO}[`date "+%H:%M:%S"`] No arguments given. Use -h / --help for documentation\n"
	exit
fi

## Help documentation
for arg in "$@"; do
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
		echo -e "\n${ECHO}[`date "+%H:%M:%S"`] Help documentation\n"
		echo -e " Options			Value				Description"
		echo -e " -m  | --manifest		String or tsv file		Manifest file or Manfiest ID corresponding to dataset to download"
		echo -e " -t  | --token			String or text file		Token ID or file containing token ID"
		echo -e " -p  | --profile 		String				Download profile (Only collab implemented)"
		echo -e " -r  | --root			Directory (writable)		Root download directory (Default: ${ROOT_DIR})"
		echo -e " -sd | --sum_dir		Directory (writable)		A directory for the download summary file - Updated per batch"
		echo -e " -sn | --sum_name		String				Name for the summary file - useful for batch scripts"
		echo -e "\n"
		echo -e " Flags"
		echo -e " --force                       Flag                            Force re-downloading of local files which exist already"
                echo -e " --keep                        Flag                            Keep full files after batch downloading"
		echo -e "\n"
		echo -e " Batching options"
		echo -e " -b  | --batch			String				Batch file downloads into discrete batches"
		echo -e "				- "NONE" 				No batching is performed. All files downloaded and retained"
		echo -e "				- "FILE"				Files are batched into N number of batchs"
		echo -e "				- "SIZE"				Files are batched in N batchs up to a cummulative file size limit"
		echo -e " -bn | --batch_num		String OR int			A filesize string (e.g 1.5Tb or 500MB) or an integer for number of batches"
		echo -e " -bs | --batch_script		String				A post download script command to run - e.g. snakemake or bash command line"
		echo -e " -h  | --help    	      	Flag				This help documentation"
		echo -e "\n"
		echo -e " Dev only"
		echo -e " --temp				Flag				Retain temp files (DEBUGGING)"
		exit 0
	fi
done

## Flags
for arg in "$@"; do
  if [[ "$arg" == "--temp" ]]; then
    TEMP="FALSE"
  fi
done

for arg in "$@"; do
  if [[ "$arg" == "--force" ]]; then
    FORCE="TRUE"
  fi
done

for arg in "$@"; do
  if [[ "$arg" == "--keep" ]]; then
    KEEP="TRUE"
  fi
done


## Arugement parsing block
while [[ $# > 1 ]]
	do 
	key="$1"
	case $key in
		-r|--root)
		ROOT_DIR=$2
		shift
		;;
		-t|--token)
		TOKEN=$2
		shift
		;;
		-p|--profile)
		PROFILE=$2
		shift
		;;
		-m|--manifest)
		MANIFEST=$2
		shift
		;;
		-b|--batch)
		BATCH=$2
		shift
		;;
		-bn|--batch_num)
		BATCH_NUMBER=$2
		shift
		;;
		-bs|--batch_script)
		BATCH_SCRIPT=$2
		shift
		;;
		-sd|--sum_dir)
                SUM_DIR=$2
                shift
                ;;
		-sn|--sum_name)
                SUM_NAME=$2
                shift
                ;;
	esac
	shift
done

# Fixed-perm post args
LOG_DIR="${ROOT_DIR}logs/log_${DATE}/"
LOG_FILE="${LOG_DIR}score_client_wrapper_${DATE}.log"

## Check root directory exists and writable 
if [ "${ROOT_DIR}" == "NULL" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Root directory not set"
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Data will be downloaded to this folder"
	exit 1
elif ! [ -d "${ROOT_DIR}" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Root directory does not exist"
	exit 1
elif ! [ -w "${ROOT_DIR}" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Root directory not writable"
	exit 1
fi

## Check current working directory is writable
if ! [ -w "${PWD}" ]; then
        echo -e "${ECHO}[`date "+%H:%M:%S"`] Current directory not writable - this is needed for certain temporary files"
        exit 1
fi

## Profile check - only collab supported currently
if [ "${PROFILE}" != "collab" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Profiles other than "collab" are not currently supported"
	echo -e "${ECHO}[`date "+%H:%M:%S"`] AWS downloads require an EC2 instance"
	echo -e "${ECHO}[`date "+%H:%M:%S"`] EGA downloads require use of the EGA client"
	exit 1
fi

# Generate primary working dirs
if ! [ -d "${ROOT_DIR}bulk/" ]; then
	mkdir ${ROOT_DIR}bulk/
fi

if ! [ -d "${ROOT_DIR}.temp/" ]; then
	mkdir ${ROOT_DIR}.temp/
fi
if ! [ -d "${ROOT_DIR}logs/" ]; then
	mkdir ${ROOT_DIR}logs/
fi
if ! [ -d "${LOG_DIR}" ]; then
	mkdir ${LOG_DIR}
fi

## Check token is valid - from file or string
if [ "${TOKEN}" == "NULL" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] No token provided"
	exit 1
else
	if ! [ -f "${TOKEN}" ]; then
		if grep -v -q -P ${ID_PATTERN} <(echo "${TOKEN}"); then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Invalid Token id format or not found"
			exit 1
		fi
	else
		TOKEN_LENGTH=$(cat ${TOKEN} | wc -l)
		if (( ${TOKEN_LENGTH} != 1 )); then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Token file contains more than one line"
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Please provide token in file with single line"
			exit 1
		else
			TOKEN=$(cat ${TOKEN})
			if grep -v -q -P ${ID_PATTERN} <(echo "${TOKEN}"); then
                        	echo -e "${ECHO}[`date "+%H:%M:%S"`] Invalid Token id format"
                        	exit 1
                	fi
		fi
	fi
fi

## Check manifest is provided
if [ "${MANIFEST}" == "NULL" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Manifest file or id was not provided"
	exit 1
else
## Check manifest is either file or id | Check file is valid
	if ! [ -f "${MANIFEST}" ]; then
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Manifest is not a file"
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Checking for valid Manifest ID"
		if grep -q -P ${ID_PATTERN} <(echo "${MANIFEST}"); then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Manifest ID valid - Downloading manifest file"
			singularity exec \
        		--bind ${LOG_DIR}:/score-client/logs/,${ROOT_DIR}bulk/:/data docker://overture/score score-client \
        		--profile ${PROFILE} \
			manifest --manifest ${MANIFEST} > ${PWD}/.temp_manifest.file
			echo -e "\n"
			MANIFEST=".temp_manifest.file"
			#MANIFEST="${PWD}/.temp_manifest.file"
		else
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Invalid manifest id format"
			exit 1
		fi
	else
		if grep -q ".tar.gz" <(echo ${MANIFEST}); then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Manifest is likely compressed tarball"
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Please uncompress and unpack first"
			exit 1
		fi
		if grep -q -P "^/mnt/.*" <(echo "${MANIFEST}"); then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Manifest file is absolute from /mnt/"
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Unknown score-client manifest read failures occur using absolute paths to files including the root"
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Use an relative path or put the manifest in the same working dir as the script"
			exit 1
		fi
		MANIFEST_COUNTS=$(head -n1 ${MANIFEST} | tr "\t" "\n" | wc -l)
		if (( ${MANIFEST_FIELDS} != ${MANIFEST_COUNTS} )); then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Manifest has wrong number of fields"
			exit 1
		fi
	fi
fi

## Get headerless manifest and manifest header
grep -v "file" ${MANIFEST} > ${ROOT_DIR}.temp/manifest_nohead.file
grep "file" ${MANIFEST} > ${ROOT_DIR}.temp/manifest_head.file
MANIFEST_NOHEAD="${ROOT_DIR}.temp/manifest_nohead.file"
MANIFEST_HEAD="${ROOT_DIR}.temp/manifest_head.file"

## Check batch variable and size/split parameters
MAX_FILE_SIZE=$(cat ${MANIFEST_NOHEAD} | sort -k6,6 | cut -f6 | head -n1)
MAX_FILE_NUMBER=$(cat ${MANIFEST_NOHEAD} | wc -l)
if [ "${BATCH}" != "NONE" ] && [ "${BATCH}" != "SIZE" ] && [ "${BATCH}" != "FILE" ]; then
        echo -e "${ECHO}[`date "+%H:%M:%S"`] Invalid batch variable give (${BATCH})"
        echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch should be either SIZE, FILE, or NONE"
        exit 1
elif [ "${BATCH}" == "FILE" ]; then 
	if [[ ! ${BATCH_NUMBER} =~ ${INTEGER_CHECK} ]]; then
        	echo -e "${ECHO}[`date "+%H:%M:%S"`] Batching by file requires an integer value as input"
        	exit 1
	elif [ "${BATCH_NUMBER}" -gt 9 ]; then
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Batching by file is limited to 9 batches - Use size batching for better batch control"
		exit 1
	elif [ "${BATCH_NUMBER}" -gt "${MAX_FILE_NUMBER}" ]; then
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Number of batches exceeds the number of primary files to be downloaded"
		exit 1
	fi
elif [ "${BATCH}" == "SIZE" ]; then
        if ! grep -i -q -P ${SIZE_PATTERN} <(echo ${BATCH_NUMBER}); then
                echo -e "File size not recognised"
        else
                if grep -i -q "T" <(echo ${BATCH_NUMBER}); then
                        TERA=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($TERA*1*10^12)/1")
                        echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch size of ${TERA}TB specified (${BATCH_NUMBER} bytes)"
                elif grep -i -q "G" <(echo ${BATCH_NUMBER}); then
                        GIGA=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($GIGA*1*10^9)/1")
                        echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch size of ${GIGA}GB specified (${BATCH_NUMBER} bytes)"
                elif grep -i -q "M" <(echo ${BATCH_NUMBER}); then
                        MEGA=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($MEGA*1*10^6)/1")
                        echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch size of ${MEGA}MB specified (${BATCH_NUMBER} bytes)"
                elif grep -i -q "K" <(echo ${BATCH_NUMBER}); then
                        KILO=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($KILO*1*10^3)/1")
                        echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch size of ${KILO}KB specified (${BATCH_NUMBER} bytes)"
                else
                        echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch size of ${BATCH_NUMBER} bytes specified"
                fi
                if [ "${BATCH_NUMBER}" -lt "${MAX_FILE_SIZE}" ]; then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch size is smaller than the single largest file (${MAX_FILE_SIZE})"
			exit 1
		fi
        fi
fi

## Tidy up previous summary file
if [ -f "${SUM_DIR}${SUM_NAME}" ]; then
	rm ${SUM_DIR}${SUM_NAME}
fi

## End of variable and parameter checks
echo -e "${ECHO}[`date "+%H:%M:%S"`] All parameters valid" | tee -a ${LOG_FILE}
echo -e "${ECHO}[`date "+%H:%M:%S"`] Files in download: $(grep -v "file" ${MANIFEST} | wc -l) (${MANIFEST})" | tee -a ${LOG_FILE}

## Download function
score_download(){
	
	## Export access token and start score-client container to download files
	MANIFEST=$1
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Exporting access token as ENV variable" | tee -a ${LOG_FILE}
	export ACCESSTOKEN=${TOKEN}
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Running score-client" | tee -a ${LOG_FILE}
	if [ "${FORCE}" == "TRUE" ]; then
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Forcing re-download of local files" | tee -a ${LOG_FILE}
		singularity exec \
			--bind ${LOG_DIR}:/score-client/logs/,${ROOT_DIR}bulk/:/data docker://overture/score score-client \
			--profile ${PROFILE} \
			download \
			--manifest ${MANIFEST} \
			--force \
			--output-dir /data 
	else
		singularity exec \
                        --bind ${LOG_DIR}:/score-client/logs/,${ROOT_DIR}bulk/:/data docker://overture/score score-client \
                        --profile ${PROFILE} \
                        download \
                        --manifest ${MANIFEST} \
                        --output-dir /data
	fi
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Score-client downloads complete" | tee -a ${LOG_FILE}
	
	## Rename log file generated by score-client
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Renaming client.log" | tee -a ${LOG_FILE}
	mv ${LOG_DIR}client.log ${LOG_DIR}client_${DATE}.log

	## If manifest was an id then assign auto-generated manifest file to the correct variable
	if grep -q ".temp_manifest.file" <(echo ${MANIFEST}); then
		mv ${MANIFEST} ${ROOT_DIR}.temp/manifest.file
		MANIFEST="${ROOT_DIR}.temp/manifest.file"
	fi

	## Generate a project by file_type directory tree
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Setting up directory tree" | tee -a ${LOG_FILE}
	grep -v "file" ${MANIFEST} | cut -f4,10 | awk -F '\t' 'BEGIN{OFS="\t";} {print($2,$1)}' | sort -u  > ${ROOT_DIR}.temp/project.list
	while read -r LINE; do
		PROJECT=$(echo "${LINE}" | cut -f1)
		FILE_TYPE=$(echo "${LINE}" | cut -f2)
		if ! [ -d "${ROOT_DIR}${PROJECT}/" ]; then
			mkdir ${ROOT_DIR}${PROJECT}/
		fi
		if ! [ -d "${ROOT_DIR}${PROJECT}/${FILE_TYPE}/" ]; then
			mkdir ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/
		fi
	done < ${ROOT_DIR}.temp/project.list

	## Populate directory tree with symlinks to the downloaded files using the manifest file
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Generating symlinks" | tee -a ${LOG_FILE}
	grep -v "file" ${MANIFEST} | cut -f4,5,10 | awk -F '\t' 'BEGIN{OFS="\t";} {print($3,$1,$2)}' > ${ROOT_DIR}.temp/file.list
	while read -r LINE; do
		PROJECT=$(echo "${LINE}" | cut -f1)
		FILE_TYPE=$(echo "${LINE}" | cut -f2)
		FILE=$(echo "${LINE}" | cut -f3)
		if [ "${FILE_TYPE}" == "BAM" ]; then
			ln -sf ${ROOT_DIR}bulk/${FILE} ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE} 
			ln -sf ${ROOT_DIR}bulk/${FILE}.bai ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.bai 
		elif [ "${FILE_TYPE}" == "VCF" ]; then
			ln -sf ${ROOT_DIR}bulk/${FILE} ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE} 
			ln -sf ${ROOT_DIR}bulk/${FILE}.tbi ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.tbi
			if ! [ -f `readlink "${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.tbi"` ]; then
				echo -e "${ECHO}[`date "+%H:%M:%S"`] $(basename "${ROOT_DIR}bulk/${FILE}.tbi") does not exist" | tee -a ${LOG_FILE}
				echo -e "${ECHO}[`date "+%H:%M:%S"`] Testing for .idx index suffix" | tee -a ${LOG_FILE}
				if [ -f "${ROOT_DIR}bulk/${FILE}.idx" ]; then
					echo -e "${ECHO}[`date "+%H:%M:%S"`] VCF uses .idx ext - Adding new symlink" | tee -a ${LOG_FILE}
					rm ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.tbi
					ln -sf ${ROOT_DIR}bulk/${FILE}.idx ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.idx
				else
					echo -e "${ECHO}[`date "+%H:%M:%S"`] Unknown index type for ${ROOT_DIR}bulk/${FILE} vcf file" | tee -a ${LOG_FILE}
					echo -e "${ECHO}[`date "+%H:%M:%S"`] This file may fail in downstream processing"| tee -a ${LOG_FILE}
				fi
			fi
		else
			ln -sf ${ROOT_DIR}bulk/${FILE} ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}
		fi
	done < ${ROOT_DIR}.temp/file.list

	## Validate symlinks
	find ${ROOT_DIR} -type l | sort > ${ROOT_DIR}.temp/symlinks.list
	echo -e "${ECHO}[`date "+%H:%M:%S"`] Validating symlink targets and names" | tee -a ${LOG_FILE}
	while read -r LINE; do
		SYM=$(basename ${LINE})
		TAR=$(basename $(readlink ${LINE}))
		if ! [ -f `readlink ${LINE}` ]; then
			echo -e "${ECHO}[`date "+%H:%M:%S"`][WARNING] Symlink target empty for ${SYM}" | tee -a ${LOG_FILE}
		elif [ "${SYM}" != "${TAR}" ]; then
			echo -e "${ECHO}[`date "+%H:%M:%S"`][WARNING] Symlink and target file have different names:" | tee -a ${LOG_FILE}
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Symlink ${LINE}" | tee -a ${LOG_FILE}
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Target file $(readlink ${LINE})" | tee -a ${LOG_FILE}
		fi
	done < ${ROOT_DIR}.temp/symlinks.list
	
	## Summary files for Project/File folders
	while read -r LINE; do
	        PROJECT=$(echo "${LINE}" | cut -f1)
                FILE_TYPE=$(echo "${LINE}" | cut -f2)
		## Root dir summary
		grep -v "file" "${MANIFEST}" | grep "${PROJECT}" \
                        | grep "${FILE_TYPE}" \
                        | cut -f4,5,9,10 \
                        | awk -F '\t' -v dir="${ROOT_DIR}${PROJECT}/${FILE_TYPE}/" 'BEGIN{OFS="\t";} {print($3,$4,$1,dir$2)}' >> ${ROOT_DIR}file_summary.txt
                grep -v "file" ${ROOT_DIR}file_summary.txt | sort -u \
                        | cat <(echo -e "sample\tproject\tfile_type\tfile") - > ${ROOT_DIR}.file_summary.txt
                mv ${ROOT_DIR}.file_summary.txt ${ROOT_DIR}file_summary.txt
		## Manifest summary
		grep -v "file" "${MANIFEST}" | grep "${PROJECT}" \
                        | grep "${FILE_TYPE}" \
                        | cut -f4,5,9,10 \
                        | awk -F '\t' -v dir="${ROOT_DIR}${PROJECT}/${FILE_TYPE}/" 'BEGIN{OFS="\t";} {print($3,$4,$1,dir$2)}' >> ${SUM_DIR}${SUM_NAME}
		grep -v "file" ${SUM_DIR}${SUM_NAME} | sort -u \
                	| cat <(echo -e "sample\tproject\tfile_type\tfile") - > ${SUM_DIR}.${SUM_NAME}
		mv ${SUM_DIR}.${SUM_NAME} ${SUM_DIR}${SUM_NAME}
		cp ${SUM_DIR}${SUM_NAME} ${LOG_DIR}
		## Per project / file type summary files
		grep -v "file" "${MANIFEST}" | grep "${PROJECT}" \
			| grep "${FILE_TYPE}" \
			| cut -f4,5,9,10 \
			| awk -F '\t' -v dir="${ROOT_DIR}${PROJECT}/${FILE_TYPE}/" 'BEGIN{OFS="\t";} {print($3,$4,$1,dir$2)}' >> \
			${ROOT_DIR}${PROJECT}/${FILE_TYPE}/file_summary.txt
		grep -v "file" ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/file_summary.txt \
			| sort -u \
			| cat <(echo -e "sample\tproject\tfile_type\tfile") - > ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/.file_summary.txt
		mv ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/.file_summary.txt ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/file_summary.txt
	done < ${ROOT_DIR}.temp/project.list

}
if [ "${BATCH}" == "NONE" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] score-client running without batching" | tee -a ${LOG_FILE}
	score_download ${MANIFEST}
else
	if [ "${BATCH}" == "FILE" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] score-client running with fixed batch sizes (${BATCH_NUMBER} batches)" | tee -a ${LOG_FILE}
		## Generate chunks by file count
		split -a 1 \
			--numeric-suffix=1 \
			--additional-suffix=.file \
			-n l/"${BATCH_NUMBER}" ${MANIFEST_NOHEAD} ${PWD}/.manifest.
		ls ${PWD}/.manifest.* > ${ROOT_DIR}.temp/chunks.list
		CHUNK_LIST="${ROOT_DIR}.temp/chunks.list"
	elif [ "${BATCH}" == "SIZE" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] score-client running with file size batches (Maximum ${BATCH_NUMBER} bytes per batch)" | tee -a ${LOG_FILE}
		## Generate chunks by file sizes
		LINE_C=1
		LINE_START=1
		LINE_MAX=$(cat ${MANIFEST_NOHEAD} | wc -l)
		BYTES=0
		CHUNK=1
		while read -r LINE; do
			LINE_BYTES=$(echo "${LINE}" | cut -f6)
			#BYTES=$(( $BYTES + $LINE_BYTES ))
			if [ $(($BYTES + $LINE_BYTES )) -ge ${BATCH_NUMBER} ]; then
				sed -n "$LINE_START,$LINE_C p" ${MANIFEST_NOHEAD} | cat ${MANIFEST_HEAD} - > ${PWD}/.manifest.${CHUNK}.file
				echo "${PWD}/.manifest.${CHUNK}.file" >> ${ROOT_DIR}.temp/chunks.list
				echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch ${CHUNK} - files ${LINE_START}-${LINE_C}" | tee -a ${LOG_FILE}
				LINE_START=$(( $LINE_C + 1 ))
				BYTES=0
				LINE_C=$(($LINE_C + 1))
				CHUNK=$(($CHUNK + 1))
			else
				BYTES=$(( $BYTES + $LINE_BYTES ))
				LINE_C=$(($LINE_C + 1))
			fi
			if [ ${LINE_C} == ${LINE_MAX} ]; then
				sed -n "$LINE_START,$LINE_C p" ${MANIFEST_NOHEAD} | cat ${MANIFEST_HEAD} - > ${PWD}/.manifest.${CHUNK}.file
				echo "${PWD}/.manifest.${CHUNK}.file" >> ${ROOT_DIR}.temp/chunks.list
				echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch ${CHUNK} - files ${LINE_START}-${LINE_C}" | tee -a ${LOG_FILE}
			fi
		done < ${MANIFEST_NOHEAD}
		CHUNK_LIST="${ROOT_DIR}.temp/chunks.list"
	fi
	CHUNK_COUNT=1
	CHUNK_TOTAL=$(cat ${CHUNK_LIST} | wc -l)
	
	## Download batchs and perform post download script - then truncate analyse files to empty
	while read -r LINE; do
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Score-client downloading batch ${CHUNK_COUNT} of ${CHUNK_TOTAL} batches" | tee -a ${LOG_FILE}
		## Run score-client function
		score_download ${LINE}
		
		## Empty file check - safety net for batching where downloaded files might be already downloaded and truncated
		while read -r FILES; do
			FILE=$(echo "${FILES}" | cut -f3)
			BULK_FILE="${ROOT_DIR}bulk/${FILE}"
			if ! [ -s "${BULK_FILE}" ]; then
				echo -e "${ECHO}[`date "+%H:%M:%S"`][WARNING] Empty file prior to running the batch script" | tee -a ${LOG_FILE}
				echo -e "${ECHO}[`date "+%H:%M:%S"`] $(basename ${BULK_FILE}) is empty" | tee -a ${LOG_FILE}
				echo -e "${ECHO}[`date "+%H:%M:%S"`] Re-run with --force if this file is needed" | tee -a ${LOG_FILE}
			fi
		done < ${ROOT_DIR}.temp/file.list	
		## Post download script command 
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Running batch job script" | tee -a ${LOG_FILE}
		echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch script command: ${BATCH_SCRIPT}" | tee -a ${LOG_FILE}
		${BATCH_SCRIPT} | tee -a ${LOG_FILE}

		## Truncating downloaded file sources
		if [ "${KEEP}" == "FALSE" ]; then
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Deleting batch downloaded files" | tee -a ${LOG_FILE}
			while read -r LINE2; do
				FILE=$(echo "${LINE2}" | cut -f3)
				echo -e "${ECHO}[`date "+%H:%M:%S"`] Batch deletion: ${FILE}" | tee -a ${LOG_FILE}
				truncate -s 0 ${ROOT_DIR}bulk/${FILE}
			done < ${ROOT_DIR}.temp/file.list
		else
			echo -e "${ECHO}[`date "+%H:%M:%S"`] Keeping batch downloaded files" | tee -a ${LOG_FILE}	
		fi
		
		## Iterate chunk count
		CHUNK_COUNT=$(($CHUNK_COUNT + 1))
	done < ${CHUNK_LIST}
fi

## Report warnings
WARNING_COUNT=$(grep -c "WARNING" ${LOG_FILE})
if [ ${WARNING_COUNT} != "0" ]; then
	echo -e "${ECHO}[`date "+%H:%M:%S"`] There were ${WARNING_COUNT} warning(s) reported" | tee -a ${LOG_FILE}
        echo -e "${ECHO}[`date "+%H:%M:%S"`] See log file for information - ${LOG_FILE}" | tee -a ${LOG_FILE}
else
        echo -e "${ECHO}[`date "+%H:%M:%S"`] Completed with no reported warnings" | tee -a ${LOG_FILE}
fi

## Clean up temp folders and files
if [ "${TEMP}" == "TRUE" ]; then
	if [ -f "${PWD}/.temp_manifest.file" ]; then
		rm ${PWD}/.temp_manifest.file
	fi

	if [ -f "${ROOT_DIR}.temp/chunks.list" ]; then
		while read -r LINE; do
			rm ${LINE}
		done < ${ROOT_DIR}.temp/chunks.list
		rm ${ROOT_DIR}.temp/chunks.list
	fi
	rm -r ${ROOT_DIR}.temp/
fi
