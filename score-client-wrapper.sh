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

# Fixed-perm
DATE=$(date "+%Y_%m_%d_%H%M%S")
ECHO=$(echo "[score-client-wrapper][`date "+%H:%M:%S"`] ")
INTEGER_CHECK="^[1-9]$|^[1-9][0-9]+$"
FLOAT_CHECK="^[0][.][0-9]+$|^[1][.][0]$"
SIZE_PATTERN="^(\d*\.?\d+)(?(?=[KMGT])([KMGT])(?:i?B)?|B?)$"
MIN_BATCH_SIZE=1000000000

## Default behaviour
if [[ $# -eq 0 ]]; then
	echo -e "\n${ECHO}No arguments given. Use -h / --help for documentation\n"
	exit
fi

## Help documentation
for arg in "$@"; do
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
		echo -e "\n${ECHO} Help documentation\n"
		echo -e " Options			Value				Description"
		echo -e " -m  | --manifest		String or tsv file		Manifest file or Manfiest ID corresponding to dataset to download"
		echo -e " -t  | --token			String or text file		Token ID or file containing token ID"
		echo -e " -p  | --profile 		String				Download profile (Only collab implemented)"
		echo -e " -r  | --root			Directory (writable)		Root download directory (Default: ${ROOT_DIR})\n"
		echo -e " Batching options"
		echo -e " -b  | --batch			String				Batch file downloads into discrete batches"
		echo -e "				- "NONE" 				No batching is performed. All files downloaded and retained"
		echo -e "				- "FILE"				Files are batched into N number of batchs"
		echo -e "				- "SIZE"				Files are batched in N batchs up to a cummulative file size limit"
		echo -e " -bn | --batch_num		String OR int			A filesize string (e.g 1.5Tb or 500MB) or an integer for number of batches"
		echo -e " -bs | --batch_script		String				A post download script command to run - e.g. snakemake or bash command line"
		echo -e " -h  | --help    	      	Flag				This help documentation\n"
		
		echo -e "Dev only"
		echo -e " --temp                	Flag				Retain temp files (DEBUGGING)"
		exit 0
	fi
done

## Flags
for arg in "$@"; do
  if [[ "$arg" == "--temp" ]]; then
    TEMP="FALSE"
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
	esac
	shift
done

# Fixed-perm post args
LOG_DIR="${ROOT_DIR}logs/"
LOG_FILE="${LOG_DIR}score_client_wrapper_${DATE}.log"
LOG_DIR="${ROOT_DIR}/logs/"

## Check root directory exists and writable 
if [ "${ROOT_DIR}" == "NULL" ]; then
	echo -e "${ECHO}Root directory not set"
	echo -e "${ECHO}Data will be downloaded to this folder"
	exit 1
elif ! [ -d "${ROOT_DIR}" ]; then
	echo -e "${ECHO}Root directory does not exist"
	exit 1
elif ! [ -w "${ROOT_DIR}" ]; then
	echo -e "${ECHO}Root directory not writable"
	exit 1
fi

## Profile check - only collab supported currently
if [ "${PROFILE}" != "collab" ]; then
	echo -e "${ECHO}Profiles other than "collab" are not currently supported"
	echo -e "${ECHO}AWS downloads require an EC2 instance"
	echo -e "${ECHO}EGA downloads require use of the EGA client"
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

## Check token is valid - from file or string
if [ "${TOKEN}" == "NULL" ]; then
	echo -e "${ECHO}No token provided"
	exit 1
else
	if ! [ -f "${TOKEN}" ]; then
		if grep -v -q -P ${ID_PATTERN} <(echo "${TOKEN}"); then
			echo -e "${ECHO}Invalid Token id format"
			exit 1
		fi
	else
		TOKEN_LENGTH=$(cat ${TOKEN} | wc -l)
		if (( ${TOKEN_LENGTH} != 1 )); then
			echo -e "${ECHO}Token file contains more than one line"
			echo -e "${ECHO}Please provide token in file with single line"
			exit 1
		else
			TOKEN=$(cat ${TOKEN})
			if grep -v -q -P ${ID_PATTERN} <(echo "${TOKEN}"); then
                        	echo -e "${ECHO}Invalid Token id format"
                        	exit 1
                	fi
		fi
	fi
fi

## Check manifest is provided
if [ "${MANIFEST}" == "NULL" ]; then
	echo -e "${ECHO}Manifest file or id was not provided"
	exit 1
else
## Check manifest is either file or id | Check file is valid
	if ! [ -f "${MANIFEST}" ]; then
		echo -e "${ECHO}Manifest is not a file"
		echo -e "${ECHO}Checking for valid Manifest ID"
		if grep -q -P ${ID_PATTERN} <(echo "${MANIFEST}"); then
			echo -e "${ECHO}Manifest ID valid - Downloading manifest file"
			singularity exec \
        		--bind ${ROOT_DIR}logs/:/score-client/logs/,${ROOT_DIR}bulk/:/data docker://overture/score score-client \
        		--profile ${PROFILE} \
			manifest --manifest ${MANIFEST} > ${HOME}/.temp_manifest.file
			echo -e "\n"
			MANIFEST="${HOME}/.temp_manifest.file"
		else
			echo -e "${ECHO}Invalid manifest id format"
			exit 1
		fi
	else
		if grep -q ".tar.gz" <(echo ${MANIFEST}); then
			echo -e "${ECHO}Manifest is likely compressed tarball"
			echo -e "${ECHO}Please uncompress and unpack first"
			exit 1
		fi
		if grep -q -P "^/mnt/.*" <(echo "${MANIFEST}"); then
			echo -e "${ECHO}Manifest file is absolute from /mnt/"
			echo -e "${ECHO}Unknown score-client manifest read failures occur using absolute paths to files on /mnt/*"
			echo -e "${ECHO}Use an relative path or cd to a directory on /mnt/"
			exit 1
		fi
		MANIFEST_COUNTS=$(head -n1 ${MANIFEST} | tr "\t" "\n" | wc -l)
		if (( ${MANIFEST_FIELDS} != ${MANIFEST_COUNTS} )); then
			echo -e "${ECHO}Manifest has wrong number of fields"
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
if [ "${BATCH}" != "NONE" ] && [ "${BATCH}" != "SIZE" ] && [ "${BATCH}" != "FILE" ]; then
        echo -e "${ECHO}Invalid batch variable give (${BATCH})"
        echo -e "${ECHO}Batch should be either SIZE, FILE, or NONE"
        exit 1
elif [ "${BATCH}" == "FILE" ] && [[ ! ${BATCH_NUMBER} =~ ${INTEGER_CHECK} ]]; then
        echo -e "${ECHO}Batching by file requires an integer value as input"
        exit 1
elif [ "${BATCH_NUMBER}" -gt 9 ] && [ "${BATCH}" == "FILE" ]; then
	echo -e "${ECHO}Batching by file is limited to 9 batches - Use size batching for better batch control"
	exit 1
elif [ "${BATCH}" == "SIZE" ]; then
        if ! grep -i -q -P ${SIZE_PATTERN} <(echo ${BATCH_NUMBER}); then
                echo -e "File size not recognised"
        else
                if grep -i -q "T" <(echo ${BATCH_NUMBER}); then
                        TERA=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($TERA*1*10^12)/1")
                        echo -e "${ECHO}Batch size of ${TERA}TB specified (${BATCH_NUMBER} bytes)"
                elif grep -i -q "G" <(echo ${BATCH_NUMBER}); then
                        GIGA=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($GIGA*1*10^9)/1")
                        echo -e "${ECHO}Batch size of ${GIGA}GB specified (${BATCH_NUMBER} bytes)"
                elif grep -i -q "M" <(echo ${BATCH_NUMBER}); then
                        MEGA=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($MEGA*1*10^6)/1")
                        echo -e "${ECHO}Batch size of ${MEGA}MB specified (${BATCH_NUMBER} bytes)"
                elif grep -i -q "K" <(echo ${BATCH_NUMBER}); then
                        KILO=$(sed 's/[A-Za-z]*//g' <(echo ${BATCH_NUMBER}))
                        BATCH_NUMBER=$(bc <<< "scale=0;($KILO*1*10^3)/1")
                        echo -e "${ECHO}Batch size of ${KILO}KB specified (${BATCH_NUMBER} bytes)"
                else
                        echo -e "${ECHO}Batch size of ${BATCH_NUMBER} bytes specified"
                fi
                if [ "${BATCH_NUMBER}" -lt "${MAX_FILE_SIZE}" ]; then
			echo -e "${ECHO}Batch size is smaller than the single largest file (${MAX_FILE_SIZE})"
			exit 1
		fi
        fi
fi

## End of variable and parameter checks
echo -e "${ECHO}All parameters valid" | tee -a ${LOG_FILE}
echo -e "${ECHO}Files in download: $(grep -v "file" ${MANIFEST} | wc -l) (${MANIFEST})" | tee -a ${LOG_FILE}

## Download function
score_download(){
	## Export access token and start score-client container to download files
	MANIFEST=$1
	echo -e "${ECHO}Exporting access token as ENV variable" | tee -a ${LOG_FILE}
	export ACCESSTOKEN=${TOKEN}
	echo -e "${ECHO}Running score-client" | tee -a ${LOG_FILE}
	singularity exec \
		--bind ${ROOT_DIR}logs/:/score-client/logs/,${ROOT_DIR}bulk/:/data docker://overture/score score-client \
		--profile ${PROFILE} \
		download \
		--manifest ${MANIFEST} \
		--output-dir /data 

	echo -e "${ECHO}Score-client downloads complete" | tee -a ${LOG_FILE}

	## Rename log file generated by score-client
	echo -e "${ECHO}Renaming client.log" | tee -a ${LOG_FILE}
	mv ${LOG_DIR}client.log ${LOG_DIR}client_${DATE}.log

	## If manifest was an id then assign auto-generated manifest file to the correct variable
	if grep -q ".temp_manifest.file" <(echo ${MANIFEST}); then
		mv ${MANIFEST} ${ROOT_DIR}.temp/manifest.file
		MANIFEST="${ROOT_DIR}.temp/manifest.file"
	fi

	## Generate a project by file_type directory tree
	echo -e "${ECHO}Setting up directory tree" | tee -a ${LOG_FILE}
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
	echo -e "${ECHO}Generating symlinks" | tee -a ${LOG_FILE}
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
				echo -e "${ECHO}${ROOT_DIR}bulk/${FILE}.tbi does not exist" | tee -a ${LOG_FILE}
				echo -e "${ECHO}Testing for .idx index suffix" | tee -a ${LOG_FILE}
				if [ -f "${ROOT_DIR}bulk/${FILE}.idx" ]; then
					echo -e "${ECHO}VCF uses .idx ext - Adding new symlink" | tee -a ${LOG_FILE}
					rm ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.tbi
					ln -sf ${ROOT_DIR}bulk/${FILE}.idx ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}.idx
				else
					echo -e "${ECHO}Unknown index type for ${ROOT_DIR}bulk/${FILE} vcf file" | tee -a ${LOG_FILE}
					echo -e "${ECHO}This file may fail in downstream processing"| tee -a ${LOG_FILE}
				fi
			fi
		else
			ln -sf ${ROOT_DIR}bulk/${FILE} ${ROOT_DIR}${PROJECT}/${FILE_TYPE}/${FILE}
		fi
	done < ${ROOT_DIR}.temp/file.list

	## Validate symlinks
	find ${ROOT_DIR} -type l | sort > ${ROOT_DIR}.temp/symlinks.list
	echo -e "${ECHO}Validating symlink targets and names" | tee -a ${LOG_FILE}
	while read -r LINE; do
		SYM=$(basename ${LINE})
		TAR=$(basename $(readlink ${LINE}))
		#echo -e "${ECHO} Validating ${SYM} to ${TAR}"
		if ! [ -f `readlink ${LINE}` ]; then
			echo -e "${ECHO}[WARNING] Symlink target empty for ${SYM}" | tee -a ${LOG_FILE}
		elif [ "${SYM}" != "${TAR}" ]; then
			echo -e "${ECHO}[WARNING] Symlink and target file have different names:" | tee -a ${LOG_FILE}
			echo -e "${ECHO}Symlink ${LINE}" | tee -a ${LOG_FILE}
			echo -e "${ECHO}Target file $(readlink	${LINE})" | tee -a ${LOG_FILE}
		fi
	done < ${ROOT_DIR}.temp/symlinks.list
	
	## Summary files for Project/File folders
	
	## Report warnings
	WARNING_COUNT=$(grep -c "WARNING" ${LOG_FILE})
	if [ ${WARNING_COUNT} != "0" ]; then
		echo -e "${ECHO}There were ${WARNING_COUNT} warning(s) reported" | tee -a ${LOG_FILE}
		echo -e "${ECHO}See log file for information - ${LOG_FILE}" | tee -a ${LOG_FILE}
	else
		echo -e "${ECHO}Completed with no reported warnings" | tee -a ${LOG_FILE}
	fi
}
if [ "${BATCH}" == "NONE" ]; then
	echo -e "${ECHO}score-client running without batching" | tee -a ${LOG_FILE}
	score_download ${MANIFEST}
else
	if [ "${BATCH}" == "FILE" ]; then
	echo -e "${ECHO}score-client running with fixed batch sizes (${BATCH_NUMBER} batches)" | tee -a ${LOG_FILE}
		## Generate chunks by file count
		split -a 1 \
			--numeric-suffix=1 \
			--additional-suffix=.file \
			-n l/"${BATCH_NUMBER}" ${MANIFEST_NOHEAD} ${HOME}/.manifest.
		ls ${HOME}/.manifest.* > ${ROOT_DIR}.temp/chunks.list
		CHUNK_LIST="${ROOT_DIR}.temp/chunks.list"
	elif [ "${BATCH}" == "SIZE" ]; then
	echo -e "${ECHO}score-client running with file size batches (Maximum ${BATCH_NUMBER} bytes per batch)" | tee -a ${LOG_FILE}
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
				sed -n "$LINE_START,$LINE_C p" ${MANIFEST_NOHEAD} | cat ${MANIFEST_HEAD} - > ${HOME}/.manifest.${CHUNK}.file
				echo "${HOME}/.manifest.${CHUNK}.file" >> ${ROOT_DIR}.temp/chunks.list
				echo -e "${ECHO}Batch ${CHUNK} - files ${LINE_START}-${LINE_C}" | tee -a ${LOG_FILE}
				LINE_START=$(( $LINE_C + 1 ))
				BYTES=0
				LINE_C=$(($LINE_C + 1))
				CHUNK=$(($CHUNK + 1))
			else
				BYTES=$(( $BYTES + $LINE_BYTES ))
				LINE_C=$(($LINE_C + 1))
			fi
			if [ ${LINE_C} == ${LINE_MAX} ]; then
				sed -n "$LINE_START,$LINE_C p" ${MANIFEST_NOHEAD} | cat ${MANIFEST_HEAD} - > ${HOME}/.manifest.${CHUNK}.file
				echo "${HOME}/.manifest.${CHUNK}.file" >> ${ROOT_DIR}.temp/chunks.list
				echo -e "${ECHO}Batch ${CHUNK} - files ${LINE_START}-${LINE_C}" | tee -a ${LOG_FILE}
			fi
		done < ${MANIFEST_NOHEAD}
		CHUNK_LIST="${ROOT_DIR}.temp/chunks.list"
	fi
	CHUNK_COUNT=1
	CHUNK_TOTAL=$(cat ${CHUNK_LIST} | wc -l)
	
	## Download batchs and perform post download script - then truncate analyse files to empty
	while read -r LINE; do
		echo -e "${ECHO}score-client downloading batch ${CHUNK_COUNT} of ${CHUNK_TOTAL} batches" | tee -a ${LOG_FILE}
		## Run score-client function
		score_download ${LINE}
		
		## Post download script command 

		${BATCH_SCRIPT}

		## Truncating downloaded file sources
		while read -r LINE2; do
			FILE=$(echo "${LINE2}" | cut -f3)
			echo -e "${ECHO}Batch deletion - removing file content for ${FILE} in ${ROOT_DIR}"
			truncate -s 0 ${ROOT_DIR}bulk/${FILE}
		done < ${ROOT_DIR}.temp/file.list
		
		## Iterate chunk count
		CHUNK_COUNT=$(($CHUNK_COUNT + 1))
	done < ${CHUNK_LIST}
fi

## Clean up temp folders and files
if [ "${TEMP}" == "TRUE" ]; then
	if [ -f "${HOME}/.temp_manifest.file" ]; then
		rm ${HOME}/.temp_manifest.file
	fi

	if [ -f "${ROOT_DIR}.temp/chunks.list" ]; then
		while read -r LINE; do
			rm ${LINE}
		done < ${ROOT_DIR}.temp/chunks.list
		rm ${ROOT_DIR}.temp/chunks.list
	fi
	rm -r ${ROOT_DIR}.temp/
fi
