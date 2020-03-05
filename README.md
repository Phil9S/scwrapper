# scwrapper

A shell script for the [score-client](https://hub.docker.com/r/overture/score/)
container image to provide an structured directory tree, download logging,
parameter checks, and batch download options.

## Quick start

Provided with a manifest file or manifest token and an access token, a given dataset
can be downloaded into the directory `data/` using the following:

```sh
# Using a manifest file
./score-client-wrapper -r data/ \
                       -m manifest_file.tsv \
                       -t f95ba6e3-2fae-f46a-1bd4-84b5b02dd392

# Using a manifest token/id
./score-client-wrapper -r data/ \
                       -m 1eb7ef06-ac99-a4a4-8a4b-2b9285acc7a0 \
                       -t f95ba6e3-2fae-f46a-1bd4-84b5b02dd392
```
Files will be downloaded using the `score-client` docker image into the `data/`
directory into a directory called `bulk`. After which a symlink-driven directory
tree is built following a project-by-filetype scheme (see [this](#bulk-downloads-and-directory-structure) section).

See [documentation](#documentation) and [examples](#real-world-example) for more information.

## Documentation
### Requirements

* Centos 7 (Other linux distros will likely work without issue)
* [Singularity](https://sylabs.io/singularity/) (&ge; version 3.2.1)
* [Score-client docker image](https://hub.docker.com/r/overture/score/) (Automatically pulled by the script)
* Bourne Again shell (bash) interpreter
* Linux command line tools provided by [GNU coreutils](https://www.gnu.org/software/coreutils/)

### ICGC access

In order to use this wrapper script and download files to your local machine,
you require access to the [ICGC data](https://dcc.icgc.org/) set. Once access has
been granted an access token can be generated. Access can be applied for [here](https://icgc.org/daco)
and details on access token usage can be found [here](https://docs.icgc.org/download/guide/#access-tokens).

### Access and manifest tokens

Both the access token and manifest ids/tokens correspond to 36 character hash strings,
corresponding to a personal access token or a set of files to download and the
`scwrapper.sh` script actively checks the validity of these tokens.

e.g. `f95ba6e3-2fae-f46a-1bd4-84b5b02dd392`

For  `--token` option this string can be provided as-is or, alternatively, a
read-only file containing a single line consisting of the access token can also
be provided in-place of the access token string, which is more secure than using
the token on the command line.

For the `--manifest` option this string can be provided as-is or, alternatively,
the manifest file can be downloaded and passed as the argument. Note that only a
decompressed, unpacked `tsv` file can be passed, as the compressed tarball from ICGC
can contain multiple manifest files.

#### Scope limitation

Because of how ICGC data is managed and organised, this wrapper will only download data from the "collaboratory" repository.
Attempts to download data from repositories outside of that scope will result in download failures and errors.

### Script options

Run the following to see the help documentation:
```sh
/score-client-wrapper.sh --help
```
__Key__
- **Required options (no defaults)**
  - Batch options are only required if running in batches

|Options               |Value                 |Description                                                             |Defaults        |
|----------------------|----------------------|------------------------------------------------------------------------|----------------|
|**-m  or --manifest** |String or tsv file    |Manifest file or Manfiest ID corresponding to dataset to download       |NULL            |
|**-t  or --token**    |String or text file   |Token ID or file containing token ID                                    |NULL            |
|-p  or --profile      |String                |Download profile (Only collab implemented)                              |collab          |
|**-r  or --root**     |Directory (writable)  |Root download directory                                                 |NULL            |
|-sd or --sum_dir      |Directory (writable)  |A directory for the download summary file - Updated per batch           |$HOME/          |
|-sn or --sum_name     |String                |Name for the summary file - useful for batch scripts                    |file_summary.txt|

|Flags                 |                      |                                                                        |                |
|----------------------|----------------------|------------------------------------------------------------------------|----------------|
|-h  or --help         |Flag                  |This help documentation                                                 |-               |
|--force               |Flag                  |Force re-downloading of local files which exist already                 |FALSE           |
|--keep                |Flag                  |Keep full files after batch downloading                                 |FALSE           |
|--temp                |Flag                  |Retain temp files (Dev usage only)                                      |FALSE           |

|Batching              |                   |                                                                           |                |
|----------------------|-------------------|---------------------------------------------------------------------------|----------------|
|**-b  or --batch**    |String             |Batch file downloads into discrete batches                                 |NONE            |
|                      |NONE               |No batching is performed. All files downloaded and retained                |-               |
|                      |FILE               |Files are batched into N number of batches (up to 9)                       |-               |
|                      |SIZE               |Files are batched in N batchs up to a cumulative file size limit           |-               |
|**-bn or --batch_num**|String OR int      |A file size string (e.g 1.5Tb or 500MB) or an integer for number of batches|1               |
|**-bs or --batch_script** |String             |A post download script command to run - e.g. snakemake or bash command line|NULL            |

### Bulk downloads and directory structure

Bulk downloads are easy to perform provided an access token is available and a
dataset is selected (see [quick start](#quick-start)). As well as downloading the
specified files, `scwrapper.sh` also generates a directory tree to organise and
maintain downloaded data whilst allowing for easy reading, sub-setting, and searching.

A directory tree is generated for the associated cancer project and file type and, for 
each file downloaded, a symlink is placed in the appropriate directory
(as well as any associated indices). Symlinks are validated for both name and target integrity.

By default, `score-client` will not re-download files which already exist but
`scwrapper.sh` will perform file and symlink validation again to make sure no
files were changed or renamed. The `--force` flag can be used to enforce re-downloading
of files regardless of if they have been downloaded previously.

Additionally a `file_summary.txt` for each file type-per-project and all downloaded files
is generated and these files are updated on-the-fly when additional files are
downloaded to keep track of all files and their location.

Lastly, each process is logged by both the `scwrapper.sh` script and `score-client`
to maintain a record of the download process and which files were downloaded.
These files are written to a submission-specific `log` directory which contains
the logging from the `scwrapper.sh` script, `score-client` image logs, and a `file_summary.txt`
for all the files associated with that specific script execution.

**Example directory tree**
```sh
.
├── bulk
│   └── {downloaded files}
├── file_summary.txt
├── logs
│   └── log_2020_02_24_195958
│       ├── file_summary.txt
│       ├── client.log
│       └── scwrapper.log
├── BTCA-SG
│   ├── VCF
│   │   ├── file_summary.txt
│   │   └── {symlinks to bulk}
│   └── BAM
│       ├── file_summary.txt
│       └── {symlinks to bulk}
└── RECA-EU
    └── VCF
        ├── file_summary.txt
        └── {symlinks to bulk}
```
### Batching downloads

Downloading files can be batched in order to limit the number of concurrent files
being downloaded at once. This particular implementation of batching is designed
to run a provided script on the downloaded files before subsequently "removing"
them in order to regulate hard disk usage.

The batching type is set by `--batch` or `-b` of which there are two implementations of batching, `FILE`
and `SIZE`. The `FILE` argument is more limited but basic if only rudimentary batching
is needed. The `SIZE` argument allows for greater flexibility by setting an upper limit
on the total cumulative size of files being downloaded and batches files accordingly.

The degree of batching or size limitations are specfied by the `-bn` or `--batch_num` option.
Where batching is set to `FILE`, the `-bn` argument can be any integer between 2 and 9.
Where batching is set to `SIZE`, the argument can be any file size string between
bytes and terabytes (e.g. `10GB,100m, 10T,1000000,10000kb, or 10Gb` are all valid),
where values without units are interpreted as bytes. Basic sanity checks are in place
to stop batching at file sizes less than the largest single file and with more batches
than files in the manifest.

In the example below, files contained with the manifest file are batched so that
each batch of files has a total size no greater than 5 terabytes, each batch is then
downloaded sequentially.

**Example of batching**
```sh
# Using a manifest token/id
./score-client-wrapper -r data/ \
                       -m 1eb7ef06-ac99-a4a4-8a4b-2b9285acc7a0  \
                       -t f95ba6e3-2fae-f46a-1bd4-84b5b02dd392 \
                       -b SIZE \
                       -bn 5T
```

By default, after a batch is complete the downloaded file is [truncated](http://man7.org/linux/man-pages/man1/truncate.1.html)
to a size of zero bytes, so file continuity is not lost and file tracking can be maintained. Warnings are issues if empty files are
passed to a batch script, as this may or may not be intended behaviour depending on user requirements.

### Batch scripts

Batching on its own is not very helpful as the files are downloaded and then immediately
"deleted" or, using the `--keep` option, ends up functioning identically to a bulk
download but with redundant intermediate steps.

The use of the `-bs` or `--batch_script` option is what makes batching worthwhile.
The argument provided to `-bs` can be any command (or series of commands or scripts)
which can run on the command line. After a batch has been downloaded, the `batch_script`
is executed and upon completion, the batch download files are removed and the next batch
downloaded.

The `scwrapper.sh` script generates a summary file, similar to those in the main
directory tree, but its location and name can be specified (`-sd` or `--sum_dir` and
`-sn` or `--sum_name`). In combination with the `batch_script`, this file can be used
to perform downstream analysis on each batch before removing the input files and
starting a new batch. The summary file in this instance is updated each batch to contain
both the current and previous batch information. It is worth being careful to not duplicate
analyses as previously run batches are still present in the summary file. A simple fix is to 
skip empty files in the script given by `-bs` or use a workflow manager.

**Example of batch scripts**
```sh
# Using a manifest token/id
./score-client-wrapper -r data/ \
                       -m 1eb7ef06-ac99-a4a4-8a4b-2b9285acc7a0  \
                       -t f95ba6e3-2fae-f46a-1bd4-84b5b02dd392 \
                       -b SIZE \
                       -bn 5Mb \
                       -sd $HOME/ \
                       -sn summaryfile.txt \
                       -bs "cat $HOME/summaryfile.txt | xargs -n1 -I {} wc -l {}"
```

In this example, the script is set to download files in 5 mebabyte batches, and after
each batch, run the batch script. In this case the batch script counts the lines in
each file, but implementing calls to larger pipelines and analysis tools should be relatively
straight forward from the summaryfile.txt.

### Real world example

Downloading BAM files for downstream analysis using [snakemake](https://snakemake.readthedocs.io/en/stable/).

In this case, hard disk space is limited on our cluster environment and `snakemake`
does not provide easily implemented size batching. Here, we can download BAM files in size-limited
batches and run the required `snakemake` pipeline from the summary file on a SLURM controlled cluster.

```sh
# Using a manifest token/id
./score-client-wrapper -r data/ \
                       -m 1eb7ef06-ac99-a4a4-8a4b-2b9285acc7a0  \
                       -t f95ba6e3-2fae-f46a-1bd4-84b5b02dd392 \
                       -b SIZE \
                       -bn 5Mb \
                       -sd ${HOME}/ \
                       -sn summaryfile.txt \
                       -bs "snakemake --config samplesheet=summaryfile.txt --cluster sbatch"
```

Because pipeline tools like `snakemake` automatically check for previously generated
outputs from input files (such as the files listed in the summary file) and that the
summary file is updated each batch, `snakemake` will process each batch in turn and
not repeat any analysis for files it previously ran.
