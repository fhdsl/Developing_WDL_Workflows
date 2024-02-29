

# Using Arrays For Parallelization and Other Use Cases

We have a workflow that runs on a single sample. What if we want to process multiple samples at once? Let's look at the various ways we can run our workflow more efficiently, as well as processing many samples in parallel. This is where WDL really shines.

In this chapter, we'll be going over:

- How to use scattered tasks to run a workflow on multiple samples at once

- How to use arrays effectively

- How to reference arrays in a task's command section

- How arrays differ from Structs

## The array type
Arrays are essentially lists of another [primitive type](https://en.wikipedia.org/wiki/Primitive_data_type). It is most common to see Array[File] in WDLs, but an array can contain integers, floats, strings, and the like. An array can only have one of a given primative type. For example, an Array[String] could contain the strings "cat" and "dog" but not the integer 1965 (however, it could have "1965" as a string).

In chapter 4, we went over the struct data type and used it to handle a myriad of reference genome files. Arrays differ from structs in that arrays are numerically indexed, which means that a member of the array can be accessed by its position in the array. On the other hand, each variable within a struct has its own name, and you use that name to reference it rather than a numerical index.

In WDL, arrays are 0 indexed, so the "first" value in an array is referenced by `[0]`. As per the WDL spec, arrays retain their order and are [immutable](https://en.wikipedia.org/wiki/Immutable_object) -- if you explicitly define an Array[String] with the members ["foo", "bar", "bizz"], you can be confident that "foo" will always be at index 0.

```
Array[String] foobarbizz = ["foo", "bar", "bizz"]
String foo = foobarbizz[0] # will always be "foo"
```

Because arrays are [immutable](https://en.wikipedia.org/wiki/Immutable_object), if you wish to add values to an array, you will need to define a new array.

## Scattered tasks
Scattered tasks allow us to run a WDL task in parallel. This is especially useful on highly scalable backends such as HPCs or the cloud, as it allows us to potentially run hundreds or even thousands of instances of a task at the same time. The most common use case for this is processing many samples at the same time, but it can also be used for processing a single sample's chromosomes in parallel, or similar situations where breaking up data into discrete "chunks" makes sense.

It should be noted that a scattered task does not work the same way as multithreading, nor does it correlate with the `cpu` WDL runtime attribute. Every instance of a scattered task takes place in a new Docker image, and is essentially "unaware" of all other instances of that scattered task, with one exception: If an instance of a scattered task errors out, a WDL executor may attempt to shut down other ongoing instances of that scattered task.

### Troubleshooting
Scattered tasks are relatively simple in theory, but the way they interact with optional types can be unintuitive. As a general rule, you should avoid using optional types as the input of a scattered task whenever possible.

Generally speaking, a WDL executor will try to run as many instances of a scattered task as it thinks your backend's hardware can handle at once. Sometimes the WDL executor will overestimate what the backend is capable of and run too many instances of a scattered task at once. This almost never happens on scalable cloud-based backends such as Terra, but isn't uncommon when running scattered tasks on a local machine.

## Making our workflow run on multiple samples at once using scattered tasks and arrays
When we originally wrote our workflow, we designed it to only run on a single sample at a time. However, we'll likely want to run this workflow on multiple samples at the same time. For some workflows, this is a great way to directly compare samples to each other, but for our purposes we simply want to avoid running a workflow 100 times if we can instead run one workflow that handles 100 samples at once.

For starters, we'll want to change our workflow-level sample variables from File to Array[File]. However, we don't need to change any of the reference genome files, because every instance of our tasks will be taking in the same reference genome files. In other words, our struct is unchanged.


```
version 1.0

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


workflow minidata_mutation_calling_chapter6 {
  input {
    Array[File] tumorSamples

    referenceGenome refGenome
    
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices

  }

```

Next, we will want to look at our chain of tasks. Each of these tasks are designed to take in a single sample. In theory, we could rewrite each task to iterate through an array of multiple samples. However, it's much simpler to keep those tasks as single-sample tasks, and simply run them on one sample at a time. To do this, we encapsulate the task calls in the workflow document with `scatter`.


```
  scatter (tumorFastq in tumorSamples) {
    call BwaMem as tumorBwaMem {
      input:
        input_fastq = tumorFastq,
        refGenome = refGenome
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
  }
```

A scatter is essentially the WDL version of a [for loop](https://en.wikipedia.org/wiki/For_loop). Every task within that loop will have access to a single File within the Array[File] that it is looping through. Within the scatter, downstream tasks can access outputs of upstream tasks like normal. They can only "see" one file at a time. However, outside the scatter, every task is considered in the context of every sample, so every output of those scattered tasks become arrays. As a result, our outputs are now Array[File] instead of just File.

```
  output {
    Array[File] tumoralignedBamSorted = tumorBwaMem.analysisReadySorted
    Array[File] tumorMarkDuplicates_bam = tumorMarkDuplicates.markDuplicates_bam
    Array[File] tumorMarkDuplicates_bai = tumorMarkDuplicates.markDuplicates_bai
    Array[File] tumoranalysisReadyBam = tumorApplyBaseRecalibrator.recalibrated_bam 
    Array[File] tumoranalysisReadyIndex = tumorApplyBaseRecalibrator.recalibrated_bai
  }
```

You can reference a full copy of this workflow at the end of this chapter.


## Referencing an array in a task

Because each task only takes in one sample, we are not directly inputting arrays into a file. However, it's important to know how to do this. If a task's input variable is an array, we must include an array separator. In WDL 1.0, this is done using the `sep=` expression placeholder. Every value in the WDL Array[String] will be separated by whatever value is declared via `sep`. In this example, that is a simple space, as that is one way how to construct a bash variable.

```
task count_words {
  input {
    Array[String] a_big_sentence
  }
  command <<<
    ARRAY_OF_WORDS=(~{sep=" " a_big_sentence})
    echo ${#ARRAY_OF_FILES[@]} >> length.txt
    # Note how the bash array uses ${} syntax, which could quickly get
    # confusing if we used that syntax for our WDL variables. This is
    # why we recommend using tilde + {} for your WDL variables.
  >>>
}
```
It's usually unnecessary to declare an Array[String], because a single String can have many words in it. That being said, an Array[String] can sometimes come in handy if it is made up of outputs from other tasks. We'll talk more about chaining tasks together in upcoming chapters.

::: {.notice data-latex="warning"}
The WDL 1.1 spec added a new built-in function, `sep()`, which replaces the `sep=` expression placeholder for arrays. This same version of the spec also notes that the `sep=` expression placeholder [are deprecated and will be removed from future versions of WDL](https://github.com/openwdl/wdl/blob/main/versions/1.1/SPEC.md#-expression-placeholder-options). For the time being, we recommend sticking with `sep=` as it is compatible with both WDL 1.0 and WDL 1.1, even though it is technically deprecated in WDL 1.1.
:::

If you're not used to working in bash, the syntax for interacting with bash arrays can be unintuitive, but you don't have to write a WDL's command section only using bash. In fact, working in another language besides bash within a WDL can be a great way to write code quickly, or perform tasks that are more advanced than what a typical bash script can handle. Just be sure to set `sep` properly to ensure that your array is interpreted correctly. In this example, we place quotation marks before and after the variable to ensure that the first and last value of the list are given beginning and ending quotation marks respectively.

```
task count_words_python {
  input {
    Array[String] a_big_sentence
  }
  command <<<
    python << CODE
    sentence = [ "~{sep='", "' a_big_sentence}" ]
    print(len(sentence))
    CODE
  >>>
  runtime {
    docker: "python:latest"
  }
}
```

## The workflow so far
```
version 1.0

## Workflow developed by Sitapriya Moorthi @ Fred Hutch LMD: 01/10/24 for use by DaSL @ Fred Hutch.
## Workflow updated on: 02/28/24 by Ash O'Farrell (UCSC)

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


workflow minidata_mutation_calling_chapter6 {
  input {
    Array[File] tumorSamples

    referenceGenome refGenome
    
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices

  }
 
  # Scatter for tumor samples   
  scatter (tumorFastq in tumorSamples) {
    call BwaMem as tumorBwaMem {
      input:
        input_fastq = tumorFastq,
        refGenome = refGenome
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
  }

  output {
    Array[File] tumoralignedBamSorted = tumorBwaMem.analysisReadySorted
    Array[File] tumorMarkDuplicates_bam = tumorMarkDuplicates.markDuplicates_bam
    Array[File] tumorMarkDuplicates_bai = tumorMarkDuplicates.markDuplicates_bai
    Array[File] tumoranalysisReadyBam = tumorApplyBaseRecalibrator.recalibrated_bam 
    Array[File] tumoranalysisReadyIndex = tumorApplyBaseRecalibrator.recalibrated_bai
  }
}
# TASK DEFINITIONS

# Align fastq file to the reference genome
task BwaMem {
  input {
    File input_fastq
    referenceGenome refGenome
    Int threads = 16
  }
  
  String base_file_name = basename(input_fastq, ".fastq")
  String ref_fasta_local = basename(refGenome.ref_fasta)

  String read_group_id = "ID:" + base_file_name
  String sample_name = "SM:" + base_file_name
  String platform = "illumina"
  String platform_info = "PL:" + platform   # Create the platform information


  command <<<
    set -eo pipefail

    mv ~{refGenome.ref_fasta} .
    mv ~{refGenome.ref_fasta_index} .
    mv ~{refGenome.ref_dict} .
    mv ~{refGenome.ref_amb} .
    mv ~{refGenome.ref_ann} .
    mv ~{refGenome.ref_bwt} .
    mv ~{refGenome.ref_pac} .
    mv ~{refGenome.ref_sa} .

    bwa mem \
      -p -v 3 -t ~{threads} -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
      ~{ref_fasta_local} ~{input_fastq} > ~{base_file_name}.sam 
    samtools view -1bS -@ 15 -o ~{base_file_name}.aligned.bam ~{base_file_name}.sam
    samtools sort -@ 15 -o ~{base_file_name}.sorted_query_aligned.bam ~{base_file_name}.aligned.bam
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

# Mark duplicates
task MarkDuplicates {
  input {
    File input_bam
  }

  String base_file_name = basename(input_bam, ".sorted_query_aligned.bam")
  String output_bam = "~{base_file_name}.duplicates_marked.bam"
  String output_bai = "~{base_file_name}.duplicates_marked.bai"
  String metrics_file = "~{base_file_name}.duplicate_metrics"

  command <<<
    gatk MarkDuplicates \
      --INPUT ~{input_bam} \
      --OUTPUT ~{output_bam} \
      --METRICS_FILE ~{metrics_file} \
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
    File markDuplicates_bam = "~{output_bam}"
    File markDuplicates_bai = "~{output_bai}"
    File duplicate_metrics = "~{metrics_file}"
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

  mv ~{refGenome.ref_fasta} .
  mv ~{refGenome.ref_fasta_index} .
  mv ~{refGenome.ref_dict} .

  mv ~{dbSNP_vcf} .
  mv ~{dbSNP_vcf_index} .

  mv ~{known_indels_sites_VCFs} .
  mv ~{known_indels_sites_indices} .

  samtools index ~{input_bam} #redundant? markduplicates already does this?

  gatk --java-options "-Xms8g" \
      BaseRecalibrator \
      -R ~{ref_fasta_local} \
      -I ~{input_bam} \
      -O ~{base_file_name}.recal_data.csv \
      --known-sites ~{dbSNP_vcf_local} \
      --known-sites ~{known_indels_sites_VCFs_local} \
      

  gatk --java-options "-Xms8g" \
      ApplyBQSR \
      -bqsr ~{base_file_name}.recal_data.csv \
      -I ~{input_bam} \
      -O ~{base_file_name}.recal.bam \
      -R ~{ref_fasta_local} \
      

  #finds the current sort order of this bam file
  samtools view -H ~{base_file_name}.recal.bam | grep @SQ | sed 's/@SQ\tSN:\|LN://g' > ~{base_file_name}.sortOrder.txt
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
```
