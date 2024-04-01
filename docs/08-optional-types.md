

# Optional types

WDL supports defining optional variables, which are denoted with a question mark next to the type declaration. These variables may or may not defined. Optional types are powerful, but they can quickly cause problems in complicated workflows. This is especially the case when working with scattered tasks. In this section, we'll go over how optional variables can be used, and where they can cause problems.

## Optional inputs
The most common use case for optional variables are optional inputs for the user to provide some sort of file, for example, a reference genome or a metadata file. Sometimes, you will want optional inputs to fall back on a known file or value.

A good place to use optional types in our workflow would be in the `bwa mem` task. `bwa mem` on default settings may attempt to use too many threads, which could cause this task to fail if it ran on weaker hardware such as a laptop. In order to allow the user to adjust how many threads `bwa mem` uses, and by extension make our WDL run on a wider variety of machines, we can edit the task to add a new variable. This new variable will replace `-t 16` in our call to `bwa mem`.

```
task BwaMem {
  input {
    File input_fastq
    referenceGenome refGenome

    # Number of threads to use - must be defined
    Int threads
  }
  command <<<
    set -eo pipefail

    mv "~{refGenome.ref_fasta}" .
    mv "~{refGenome.ref_fasta_index}" .
    mv "~{refGenome.ref_dict}" .
    mv "~{refGenome.ref_amb}" .
    mv "~{refGenome.ref_ann}" .
    mv "~{refGenome.ref_bwt}" .
    mv "~{refGenome.ref_pac}" .
    mv "~{refGenome.ref_sa}" .

    bwa mem \
      -p -v 3 -t ~{threads} -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
      "~{ref_fasta_local}" "~{input_fastq}" > "~{base_file_name}.sam" 
    samtools view -1bS -@ 15 -o "~{base_file_name}.aligned.bam" "~{base_file_name}.sam"
    samtools sort -@ 15 -o "~{base_file_name}.sorted_query_aligned.bam" "~{base_file_name}.aligned.bam"
[...]
}
```

Because `~{threads}` is an integer variable, it cannot have a space in it, so we don't need to surround `~{threads}` with quotation marks like we should String or File variables.

Now we can set `Int? bwa_mem_threads` as a workflow-level optional input. Making it optional means that users who do not want to think about threads -- perhaps they're using an HPC or other powerful backend -- do not have to worry about filling in that value. In the workflow body, when we call `bwa mem`, the value of `bwa_mem_threads` is passed to the `BwaMem` task.

```
workflow mutation_calling {
  input {
    Array[File] tumorSamples
    File normalFastq

    referenceGenome refGenome

    # Optional variable for bwa mem
    Int? bwa_mem_threads
    
    # Files for specific tools
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices
    File af_only_gnomad
    File af_only_gnomad_index

    # Annovar options
    String annovar_protocols
    String annovar_operation
  }
  call BwaMem as normalBwaMem {
    input:
      input_fastq = normalFastq,
      refGenome = refGenome,
      threads = bwa_mem_threads
  }
[...]
}
```

But what happens if the workflow-level variable `bwa_mem_threads` isn't defined? The task `BwaMem` will then get no value for the task-level variable `threads`. This will cause an error at runtime. We can't solve this merely by making the task level variable optional too -- otherwise, if `threads` isn't defined, our `bwa mem` call will provide `-t  ` without a number after it, which is invalid.

One way to address this is with the WDL built-in function `select_first()`, which takes in an array of values. In the workflow body, we can use this plus a fallback value (or another variable) to ensure that the `BwaMem` task always gets a valid integer for the `threads` argument.

```
  call BwaMem as normalBwaMem {
    input:
      input_fastq = normalFastq,
      refGenome = refGenome,
      threads = select_first([bwa_mem_threads, 16])
  }
```

This is a perfectly valid way of doing things, but the task itself still relies on that variable being defined. In the context of our workflow, that doesn't matter. However, keep in mind it is a common practice to reuse code for multiple scripts -- whether that is directly importing other WDL tasks using WDL's importing feature, or simply copy-pasting boilerplate code. With that in mind, it's a good idea to make tasks as "stand-alone" as possible, and not reliant on the workflow calling them to use `select_first()`.

As such, it's more common to make the task itself handle this by providing a fallback value, like so:

```
task BwaMem {
  input {
    File input_fastq
    referenceGenome refGenome
    Int threads = 16  # if a workflow passes an optional variable with no value, fall back to 16
  }
  [...]
}
```

<details>

<summary><b>Here's another way of providing a fallback value for optional inputs within a task.</b></summary>


In the following task, the phylogenetic tree program UShER expects a reference genome, an input phylogenetic tree, samples in the form of diff files, and an output file name. However, the Docker image we're using (`ashedpotatoes/usher-plus:0.0.2`) already contains the H37Rv reference genome, which is the standard reference genome for *Mycobacterium tuberculosis*. If we are working with tuberuclosis samples, there is no reason to provide a reference genome -- we might as well use the one that's already in the Docker image.

```
task usher_sampled_diff {
	input {
		File diff
		File input_tree  # in MAT format, extension should be .pb
		String output_file_name
		File? ref_genome
	}

	command <<<
		if [[ "~{ref_genome}" = "" ]]
		then
            # if not defined, fall back to H37Rv in the Docker image
			ref="/HOME/usher/ref/Ref.H37Rv/ref.fa"
		else
			ref="~{ref_genome}"
		fi

		usher-sampled --diff "~{diff}" \
			-i "${input_tree}" \
			--ref "$ref" \
			-o "~{output_file_name}"
	>>>

	runtime {
		docker: "ashedpotatoes/usher-plus:0.0.2"
	}

	output {
		File usher_tree = output_file_name
	}
}
```

</details>

## Optional outputs
Optional outputs are usually created by explicitly declaring a task or workflow's output variable to be optional. They can also be created by enclosing a task within an if-block, which will cause all outputs of that task to be considered optional.

### Declaring a task's output to be optional
Most backends will save the task-level outputs of a task, even if those outputs are not workflow-level outputs. This can be very useful if you want to be able to check intermediate files, or perhaps log files for certain bioinformatic tools. However, if you're not actively debugging, those files may take up a lot of space on your backend if you're running on many samples over time.

You could change the workflow every time you wish to keep those intermediate inputs, but it would be easier to make the output optional.


```
task usher_sampled_diff {
	input {
		File diff
		File input_tree  # in MAT format, extension should be .pb
		String output_file_name
		File? ref_genome
        Boolean detailed_clades
	}
    # UShER will output clade information if you pass the -D flag to it, but
    # we don't want users to have to type in flags as a String variable. Instead,
    # we just make a Boolean variable called detailed_clades, and outside the inputs
    # section, we write the string "-D" if detailed_clades is true, or an empty string
    # if detailed_clades is false.
    String detailed_clades_flag = if !(detailed_clades) then "" else "-D "

	command <<<
		if [[ "~{ref_genome}" = "" ]]
		then
			ref="/HOME/usher/ref/Ref.H37Rv/ref.fa"
		else
			ref="~{ref_genome}"
		fi

		usher-sampled ~{detailed_clades_flag} \ 
            --diff "~{diff}" \
			-i "${input_tree}" \
			--ref "$ref" \
			-o "~{output_file_name}"
	>>>

	runtime {
		docker: "ashedpotatoes/usher-plus:0.0.2"
	}

	output {
		File usher_tree = output_file_name
		File? clades = "clades.txt" # only if detailed_clades = true
	}
}
```

If we want, we can make this task-level output a workflow-level output -- perhaps we use a backend that does not save task-level outputs, or it is simply easier to access workflow-level outputs on this particular backend. Provided that the task is not scattered, this is very easy to do. (We'll talk about scattered tasks later, as they complicate matters.) In the workflow output sections, we simply define the output as optional like we did in the task itself.

### Making an entire task optional
Let's say we want to make an entire task optional. Perhaps it provides additional QC information, or isn't relevent to certain data types.

Although WDL has a concept of `if`, it does not have any concept of `else`, so to make mutually exclusive tasks, you essentially need use two mutually exclusive if-statements. In the example below, we use two mutually exclusive if-statements to decide whether to run task_x or task_y. This is a valid way of doing things, and will work as expected:

```
workflow do_x_or_y {
    input {
        Boolean do_x = true # if true do task_x, if false do task_y
        File some_input
    }
    if (do_x = true) {
        call task_x {
            input:
                some_input = some_input
        }
    }
    if (do_x = false) {
        call task_y {
         input:
                some_input = some_input
        }
    }
}
```

However, we need to keep in mind that WDL is not "aware" that these two tasks are mutually exclusive. You and I both know that if task_x has run, then task_y must not have run, but your WDL executor does not know this. So, as a consequence, you cannot use mutually exclusive if-blocks to set a variable to a particular value.

```
# this workflow will fail miniwdl check or womtool
workflow do_x_or_y {
    input {
        Boolean do_x = true # if true do task_x, if false do task_y
        File some_input
    }
    if (do_x = true) {
        Int some_variable = 10  # this is problematic, even though only one of these if blocks will execute!
        call task_x {
            input:
                some_input = some_input
        }
    }
    if (do_x = false) {
        Int some_variable = 5  # this is problematic, even though only one of these if blocks will execute!
        call task_y {
         input:
                some_input = some_input
        }
    }
}
```
Another consequence is that both of your mutually exclusive tasks' outputs will be considered optional types, even though you can be certain that set of outputs absolutely do exist and one set of outputs absolutely do not exist.

```
workflow do_x_or_y {
    input {
        Boolean do_x = true # if true do task_x, if false do task_y
        File some_input
    }
    if (do_x = true) {
        call task_x {
            input:
                some_input = some_input
        }
    }
    if (do_x = false) {
        call task_y {
         input:
                some_input = some_input
        }
    }

    outputs {
        # these both MUST be optional
        File? task_x_output = task_x.something
        File? task_y_output = task_y.something
    }
}
```

<details>

<summary><b>Checking if a variable is defined</b></summary>


You can check if a variable is defined at runtime using the WDL built-in `defined()`, which returns a Boolean value. However, `defined()` can give unexpected output, as we will go over later. For the time being, let's use a simple example where we set a Boolean variable via `defined()`. This will work as expected -- if task_x ran and created the output `task_x.something`, then `did_x_run` will be true, and so on.

```
workflow do_x_or_y {
    input {
        Boolean do_x = true # if true do task_x, if false do task_y
        File some_input
    }
    if (do_x = true) {
        call task_x {
            input:
                some_input = some_input
        }
    }
    if (do_x = false) {
        call task_y {
         input:
                some_input = some_input
        }
    }

    # these work as you would expect
    Boolean did_x_run = defined(task_x.something)
    Boolean did_y_run = defined(task_y.something)

    outputs {
        File? task_x_output = task_x.something
        File? task_y_output = task_y.something
        Boolean did_x_run = did_x_run
        Boolean did_y_run = did_y_run
    }
}
```

Note that although you could decide whether or not to execute a task by wrapping that task in a `defined()` if-block, you cannot use `defined()` to coerce a variable. It's generally best to use `select_first()` for type coercion, although we will mention some exceptions when it comes to arrays.

```
  # if some_integer has type Int?, we cannot coerce it like this:
  if defined(some_integer) {
      Int real_some_integer = some_integer
  }
  # because outside of the if-block, real_some_integer is considered optional
```

You should not use `defined()` with optional arrays, as it often acts in unexpected ways. It is very easy to accidentally create a `defined()` check that always returns true, as WDL executors may define "optional" arrays even if they have no values. For example, let's consider task_x and task_y again. To recap, these are mutually exclusive tasks which each output a single File. If these tasks are scattered from outside their respective if-blocks, the their outputs are no longer File?, instead, they are arrays. But are they arrays of optional File?s, or are the arrays themselves optional? Let's try to find out:

```
workflow do_x_or_y {
    input {
        Boolean do_x = true # if true do task_x, if false do task_y
        Array[File] some_inputs
    }
    scatter(some_input in some_inputs) {
        if (do_x = true) {
            call task_x {
                input:
                    some_input = some_input
            }
        }
        if (do_x = false) {
            call task_y {
            input:
                    some_input = some_input
            }
        }
    }

    # these both always return true!
    Boolean did_x_run = defined(task_x.something)
    Boolean did_y_run = defined(task_y.something)

    outputs {
        File? task_x_output = task_x.something
        File? task_y_output = task_y.something
        Boolean did_x_run = did_x_run
        Boolean did_y_run = did_y_run
    }
}
```

Instead of using `defined()` on an array, consider simply checking its length. An empty array has a length of 0, so if the length of an array is greater than 1, you know that there is at least one item existing in that array.

</details>


<details>

<summary><b>Working with optional arrays and advanced usage of `select_first()`</b></summary>

Coercing arrays with optional components

Optional arrays can be difficult to work with. One of the reasons for this is that they sometimes give unexpected values for `defined()`. As mentioned earlier, this can be somewhat allievated by checking the length of an array rather than whether or not it is defined, but the problems do not end there: Attempting to scatter on an optional array can cause issues that are difficult to debug.

It's generally best to coerce optional arrays into not-optional arrays as much as possible. Thankfully, we can use `select_all()` to select only the defined elements of an array. For our example above, we can go even further by creating an array that will always have a defined value, whether or not `do_x` is true. We combine the power of `select_all()` and `flatten()` to create the following:

```
Array[File] x_or_y_outfiles = flatten(select_all(x.outfile), select_all(y.outfile))
```

Make sure not to use `flatten(select_all(x.outfile, y.outfile))`! That would result in an Array[File] that has a null value, which can cause hard-to-diagnose issues later on in your pipeline.

If you're absolutely certain your variable, in this particular scope, is defined, you can make the second member of the `select_first()` array a random bogus fallback value. You may want to add a comment to prevent you or other programmers accidentally breaking things should they edit the code later.

```
if defined(some_integer) { # needed to define real_some_integer, beware of changing this!
    Int real_some_integer = select_first([some_integer, 1975])
}
```

</details>

## The final workflow

At this point, we've completeled our workflow. Here's what it looks like now:

```
version 1.0
## WDL 101 example workflow
## 
## This WDL workflow is intended to be used along with the WDL 101 docs. 
## This workflow should be used for inspiration purposes only. 
##
## We use three samples 
## Samples:
## MOLM13: Normal sample
## CALU1: KRAS G12C mutant
## HCC4006: EGFR Ex19 deletion mutant 
##
## Input requirements:
## - combined fastq files for chromosome 12 and 7 +/- 200bp around the sites of mutation only
##
## Output Files:
## - An aligned bam for all 3 samples (with duplicates marked and base quality recalibrated)
## 
## Workflow developed by Sitapriya Moorthi, Chris Lo and Taylor Firman @ Fred Hutch and Ash (Aisling) O'Farrell @ UCSC LMD: 02/28/24 for use @ Fred Hutch.

struct referenceGenome {
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
    String ref_name
}


workflow mutation_calling {
  input {
    Array[File] tumorSamples
    File normalFastq

    referenceGenome refGenome

    # Optional variable for bwa mem
    Int? bwa_mem_threads
    
    # Files for specific tools
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices
    File af_only_gnomad
    File af_only_gnomad_index

    # Annovar options
    String annovar_protocols
    String annovar_operation
  }

  # First, process the non-tumor normal sample
  call BwaMem as normalBwaMem {
    input:
      input_fastq = normalFastq,
      refGenome = refGenome,
      threads = bwa_mem_threads
  }
  
  call MarkDuplicates as normalMarkDuplicates {
    input:
      input_bam = normalBwaMem.analysisReadySorted
  }

  call ApplyBaseRecalibrator as normalApplyBaseRecalibrator {
    input:
      input_bam = normalMarkDuplicates.markDuplicates_bam,
      input_bam_index = normalMarkDuplicates.markDuplicates_bai,
      dbSNP_vcf = dbSNP_vcf,
      dbSNP_vcf_index = dbSNP_vcf_index,
      known_indels_sites_VCFs = known_indels_sites_VCFs,
      known_indels_sites_indices = known_indels_sites_indices,
      refGenome = refGenome
  }
 
  # Scatter for "tumor" samples   
  scatter (tumorSample in tumorSamples) {
    call BwaMem as tumorBwaMem {
      input:
        input_fastq = tumorSample,
        refGenome = refGenome,
        threads = bwa_mem_threads
    }
    
    call MarkDuplicates as tumorMarkDuplicates {
      input:
        input_bam = tumorBwaMem.analysisReadySorted
    }

    call ApplyBaseRecalibrator as tumorApplyBaseRecalibrator{
      input:
        input_bam = tumorMarkDuplicates.markDuplicates_bam,
        input_bam_index = tumorMarkDuplicates.markDuplicates_bai,
        dbSNP_vcf = dbSNP_vcf,
        dbSNP_vcf_index = dbSNP_vcf_index,
        known_indels_sites_VCFs = known_indels_sites_VCFs,
        known_indels_sites_indices = known_indels_sites_indices,
        refGenome = refGenome
      }

    call Mutect2Paired {
      input:
        tumor_bam = tumorApplyBaseRecalibrator.recalibrated_bam,
        tumor_bam_index = tumorApplyBaseRecalibrator.recalibrated_bai,
        normal_bam = normalApplyBaseRecalibrator.recalibrated_bam,
        normal_bam_index = normalApplyBaseRecalibrator.recalibrated_bai,
        refGenome = refGenome,
        genomeReference = af_only_gnomad,
        genomeReferenceIndex = af_only_gnomad_index
    }

  call annovar {
    input:
      input_vcf = Mutect2Paired.output_vcf,
      ref_name = refGenome.ref_name,
      annovar_operation = annovar_operation,
      annovar_protocols = annovar_protocols
  }
}

  output {
    Array[File] tumoralignedBamSorted = tumorBwaMem.analysisReadySorted
    Array[File] tumorMarkDuplicates_bam = tumorMarkDuplicates.markDuplicates_bam
    Array[File] tumorMarkDuplicates_bai = tumorMarkDuplicates.markDuplicates_bai
    Array[File] tumoranalysisReadyBam = tumorApplyBaseRecalibrator.recalibrated_bam 
    Array[File] tumoranalysisReadyIndex = tumorApplyBaseRecalibrator.recalibrated_bai
    File normalalignedBamSorted = normalBwaMem.analysisReadySorted
    File normalmarkDuplicates_bam = normalMarkDuplicates.markDuplicates_bam
    File normalmarkDuplicates_bai = normalMarkDuplicates.markDuplicates_bai
    File normalanalysisReadyBam = normalApplyBaseRecalibrator.recalibrated_bam 
    File normalanalysisReadyIndex = normalApplyBaseRecalibrator.recalibrated_bai
    Array[File] Mutect2Paired_Vcf = Mutect2Paired.output_vcf
    Array[File] Mutect2Paired_VcfIndex = Mutect2Paired.output_vcf_index
    Array[File] Mutect2Paired_AnnotatedVcf = annovar.output_annotated_vcf
    Array[File] Mutect2Paired_AnnotatedTable = annovar.output_annotated_table
  }

  parameter_meta {
    tumorSamples: "Tumor .fastq, one sample per .fastq file (expects Illumina)"
    normalFastq: "Non-tumor .fastq (expects Illumina)"

    dbSNP_vcf: "dbSNP VCF for mutation calling"
    dbSNP_vcf_index: "dbSNP VCF index"
    known_indels_sites_VCFs: "Known indel site VCF for mutation calling"
    known_indels_sites_indices: "Known indel site VCF indicies"
    af_only_gnomad: "gnomAD population allele fraction for mutation calling"
    af_only_gnomad_index: "gnomAD population allele fraction index"

    annovar_protocols: "annovar protocols: see https://annovar.openbioinformatics.org/en/latest/user-guide/startup"
    annovar_operation: "annovar operation: see https://annovar.openbioinformatics.org/en/latest/user-guide/startup"
  }
}

####################
# Task definitions #
####################

# Align fastq file to the reference genome
task BwaMem {
  input {
    File input_fastq
    referenceGenome refGenome
    Int threads = 16  # if a workflow passes an optional variable with no value, fall back to 16
  }
  
  String base_file_name = basename(input_fastq, ".fastq")
  String ref_fasta_local = basename(refGenome.ref_fasta)

  String read_group_id = "ID:" + base_file_name
  String sample_name = "SM:" + base_file_name
  String platform_info = "PL:illumina"


  command <<<
    set -eo pipefail

    mv "~{refGenome.ref_fasta}" .
    mv "~{refGenome.ref_fasta_index}" .
    mv "~{refGenome.ref_dict}" .
    mv "~{refGenome.ref_amb}" .
    mv "~{refGenome.ref_ann}" .
    mv "~{refGenome.ref_bwt}" .
    mv "~{refGenome.ref_pac}" .
    mv "~{refGenome.ref_sa}" .

    bwa mem \
      -p -v 3 -t ~{threads} -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
      "~{ref_fasta_local}" "~{input_fastq}" > "~{base_file_name}.sam" 
    samtools view -1bS -@ 15 -o "~{base_file_name}.aligned.bam" "~{base_file_name}.sam"
    samtools sort -@ 15 -o "~{base_file_name}.sorted_query_aligned.bam" "~{base_file_name}.aligned.bam"
  >>>

  output {
    File analysisReadySorted = "~{base_file_name}.sorted_query_aligned.bam"
  }
  
  runtime {
    memory: "48 GB"
    cpu: 16
    docker: "ghcr.io/getwilds/bwa:0.7.17"
  }
}

# Mark duplicates on a BAM file
task MarkDuplicates {
  input {
    File input_bam
  }

  String base_file_name = basename(input_bam, ".sorted_query_aligned.bam")

  command <<<
    gatk MarkDuplicates \
      --INPUT "~{input_bam}" \
      --OUTPUT "~{base_file_name}.duplicates_marked.bam" \
      --METRICS_FILE "~{base_file_name}.duplicate_metrics" \
      --CREATE_INDEX true \
      --OPTICAL_DUPLICATE_PIXEL_DISTANCE 100 \
      --VALIDATION_STRINGENCY SILENT
  >>>

  runtime {
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
    memory: "48 GB"
    cpu: 4
  }

  output {
    File markDuplicates_bam = "~{base_file_name}.duplicates_marked.bam"
    File markDuplicates_bai = "~{base_file_name}.duplicates_marked.bai"
    File duplicate_metrics = "~{base_file_name}.duplicates_marked.bai"
  }
}

# Base quality recalibration
task ApplyBaseRecalibrator {
  input {
    File input_bam
    File input_bam_index
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices
    referenceGenome refGenome
  }
  
  String base_file_name = basename(input_bam, ".duplicates_marked.bam")
  
  String ref_fasta_local = basename(refGenome.ref_fasta)
  String dbSNP_vcf_local = basename(dbSNP_vcf)
  String known_indels_sites_VCFs_local = basename(known_indels_sites_VCFs)


  command <<<
  set -eo pipefail

  mv "~{refGenome.ref_fasta}" .
  mv "~{refGenome.ref_fasta_index}" .
  mv "~{refGenome.ref_dict}" .

  mv "~{dbSNP_vcf}" .
  mv "~{dbSNP_vcf_index}" .

  mv "~{known_indels_sites_VCFs}" .
  mv "~{known_indels_sites_indices}" .

  samtools index "~{input_bam}"

  gatk --java-options "-Xms8g" \
      BaseRecalibrator \
      -R "~{ref_fasta_local}" \
      -I "~{input_bam}" \
      -O "~{base_file_name}.recal_data.csv" \
      --known-sites "~{dbSNP_vcf_local}" \
      --known-sites "~{known_indels_sites_VCFs_local}" \
      

  gatk --java-options "-Xms8g" \
      ApplyBQSR \
      -bqsr "~{base_file_name}.recal_data.csv" \
      -I "~{input_bam}" \
      -O "~{base_file_name}.recal.bam" \
      -R "~{ref_fasta_local}" \
      

  # finds the current sort order of this bam file
  samtools view -H "~{base_file_name}.recal.bam" | grep @SQ | sed 's/@SQ\tSN:\|LN://g' > "~{base_file_name}.sortOrder.txt"
  >>>

  output {
    File recalibrated_bam = "~{base_file_name}.recal.bam"
    File recalibrated_bai = "~{base_file_name}.recal.bai"
    File sortOrder = "~{base_file_name}.sortOrder.txt"
  }
  runtime {
    memory: "36 GB"
    cpu: 2
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
  }
}

# Variant calling via mutect2 (tumor-and-normal mode)
task Mutect2Paired {
  input {
    File tumor_bam
    File tumor_bam_index
    File normal_bam
    File normal_bam_index
    referenceGenome refGenome
    File genomeReference
    File genomeReferenceIndex
  }

  String base_file_name_tumor = basename(tumor_bam, ".recal.bam")
  String ref_fasta_local = basename(refGenome.ref_fasta)
  String genomeReference_local = basename(genomeReference)

  command <<<
    set -eo pipefail

    mv "~{refGenome.ref_fasta}" .
    mv "~{refGenome.ref_fasta_index}" .
    mv "~{refGenome.ref_dict}" .

    mv "~{genomeReference}" .
    mv "~{genomeReferenceIndex}" .

    gatk --java-options "-Xms16g" Mutect2 \
      -R "~{ref_fasta_local}" \
      -I "~{tumor_bam}" \
      -I "~{normal_bam}" \
      -O preliminary.vcf.gz \
      --germline-resource "~{genomeReference_local}" \

    gatk --java-options "-Xms16g" FilterMutectCalls \
      -V preliminary.vcf.gz \
      -O "~{base_file_name_tumor}.mutect2.vcf.gz" \
      -R "~{ref_fasta_local}" \
      --stats preliminary.vcf.gz.stats \
  >>>

  runtime {
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
    memory: "24 GB"
    cpu: 1
  }

  output {
    File output_vcf = "${base_file_name_tumor}.mutect2.vcf.gz"
    File output_vcf_index = "${base_file_name_tumor}.mutect2.vcf.gz.tbi"
  }
}

# Annotate VCF using annovar
task annovar {
  input {
    File input_vcf
    String ref_name
    String annovar_protocols
    String annovar_operation
  }
  String base_vcf_name = basename(input_vcf, ".vcf.gz")
  
  command <<<
    set -eo pipefail
  
    perl annovar/table_annovar.pl "~{input_vcf}" annovar/humandb/ \
      -buildver "~{ref_name}" \
      -outfile "~{base_vcf_name}" \
      -remove \
      -protocol "~{annovar_protocols}" \
      -operation "~{annovar_operation}" \
      -nastring . -vcfinput
  >>>
  runtime {
    docker: "ghcr.io/getwilds/annovar:~{ref_name}"
    cpu: 1
    memory: "2GB"
  }
  output {
    File output_annotated_vcf = "~{base_vcf_name}.${ref_name}_multianno.vcf"
    File output_annotated_table = "~{base_vcf_name}.${ref_name}_multianno.txt"
  }
}
```
