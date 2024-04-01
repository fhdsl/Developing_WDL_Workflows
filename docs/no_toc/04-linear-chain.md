

# Connecting multiple tasks together in a linear chain

Now that you have a first task in a workflow up and running, the next step is to continue building out the workflow as described in our Workflow Plan:

1.  `BwaMem` aligns the samples to the reference genome.
2.  `MarkDuplicates` marks PCR duplicates.
3.  `ApplyBaseRecalibrator` applies base recalibration.
4.  `Mutect2` performs somatic mutation calling. For this current iteration, we start with `Mutect2TumorOnly` which only uses the tumor sample.
5.  `annovar` annotates the called somatic mutations.

We do this via a **linear chain**, in which we feed the output of one task to the input of the next task. Let's see how to build a linear chain in a workflow.

## How to connect tasks together in a workflow

We can easily connect tasks together because of the following: *The output variables of a task can be accessed at the workflow level as inputs for the subsequent task.*

For instance, let's see the output of our `BwaMem` task.

```         
output {
    File analysisReadyBam = "~{base_file_name}.aligned.bam"
    File analysisReadySorted = "~{base_file_name}.sorted_query_aligned.bam"
  }
```

The File variables `analysisReadyBam` and `analysisReadySorted` can now be accessed anywhere in the workflow block after the `BwaMem` task as `BwaMem.analysisReadyBam` and `BwaMem.analysisReadySorted`, respectively. Therefore, when we call the `MarkDuplicates` task, we can pass it the input `BwaMem.analysisReadySorted` from the `BwaMem` task:


```         
workflow minidata_mutation_calling_v1 {
  input {
    # Sample info
    File sampleFastq
    # Reference Genome information
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
  }
    
  # Map reads to reference
  call BwaMem {
    input:
      input_fastq = sampleFastq,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      ref_amb = ref_amb,
      ref_ann = ref_ann,
      ref_bwt = ref_bwt,
      ref_pac = ref_pac,
      ref_sa = ref_sa
  }
  
  call MarkDuplicates {
    input:
      input_bam = BwaMem.analysisReadySorted
  }
}
```

::: {.notice data-latex="notice"}
Resources:

<ul>

<li>For a basic introduction to linear chain, see [OpenWDL Docs](https://docs.openwdl.org/en/latest/WDL/Linear_chaining/)' introduction. </li>

<li>To see other examples of linear chain and variations, see [OpenWDL Docs](https://docs.openwdl.org/en/latest/WDL/add_plumbing/)'s section on workflow plumbing. </li>

</ul>
:::




## Writing `MarkDuplicates` task

Of course, the task `MarkDuplicates` hasn't been written yet! Let's go through it together:

### Input

The task takes an input bam file that has been aligned to the reference genome. It needs to be a File `input_bam` based on how we introduced it in the workflow above. That is easy to write up:

```         
task MarkDuplicates {
  input {
    File input_bam
  }
}
```

### Private variables in the task

Similar to the `BwaMem` task, we will name our output files based on the base name of the original input file in the workflow. Therefore, it makes sense to create a private String variable `base_file_name` that contains this base name of `input_bam`. We will use `base_file_name` in the Command section to specify the output bam and metrics files.

```         
task MarkDuplicates {
  input {
    File input_bam
  }
  String base_file_name = basename(input_bam, ".sorted_query_aligned.bam")
}
```

### Command

As we have been doing all along, we refer to any defined variables from the input or private variables using \~{this} syntax.

```         
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
}
```

### Runtime and Output

We specify a different Docker image that contains the GATK software, and the relevant computing needs. We also specify three different output files, two of which are specified in the command section, and the third is a bam index file that is automatically created by the command section.

Below is the task all together. It has a form very similar to our first task `BwaMem`.

```         
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
    docker: "broadinstitute/gatk:4.1.4.0"
    memory: "48 GB"
    cpu: 4
  }
  
  output {
    File markDuplicates_bam = "~{base_file_name}.duplicates_marked.bam"
    File markDuplicates_bai = "~{base_file_name}.duplicates_marked.bai"
    File duplicate_metrics = "~{base_file_name}.duplicate_metrics"
  }
}
```

### Testing the workflow

As before, when you add a new task to the workflow, you should always test that it works on your test sample. To check that `MarkDuplicates` is indeed marking PCR duplicates, you could check for the presence of the [PCR duplicate flag in reads](https://gatk.broadinstitute.org/hc/en-us/articles/360051306171-MarkDuplicates-Picard), which has a decimal value of 1024 in the SAM Flags Field.

## The rest of the linear chain workflow

We build out the rest of the tasks in a very similar fashion. Tasks `ApplyBaseRecalibrator` and `Mutect2TumorOnly` both have files that need to be localized, but otherwise all the tasks have a very similar form as `BwaMem` and `MarkDuplicates`. For this current iteration, we use only the tumor sample for mutation calling. In the following chapters, we will use additional WDL features to make use of tumor and normal samples for mutation calling. 

```         
version 1.0

workflow minidata_mutation_calling_v1 {
  input {
    # Sample info
    File sampleFastq
    # Reference Genome information
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
    File dbSNP_vcf
    File dbSNP_vcf_index
    File known_indels_sites_VCFs
    File known_indels_sites_indices
    File af_only_gnomad
    File af_only_gnomad_index
    File annovarTAR
    String annovar_protocols
    String annovar_operation
    String ref_name
  }
    
  # Map reads to reference
  call BwaMem {
    input:
      input_fastq = sampleFastq,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index,
      ref_dict = ref_dict,
      ref_amb = ref_amb,
      ref_ann = ref_ann,
      ref_bwt = ref_bwt,
      ref_pac = ref_pac,
      ref_sa = ref_sa
  }
  
  call MarkDuplicates {
    input:
      input_bam = BwaMem.analysisReadySorted
  }

  call ApplyBaseRecalibrator {
    input:
      input_bam = MarkDuplicates.markDuplicates_bam,
      input_bam_index = MarkDuplicates.markDuplicates_bai,
      dbSNP_vcf = dbSNP_vcf,
      dbSNP_vcf_index = dbSNP_vcf_index,
      known_indels_sites_VCFs = known_indels_sites_VCFs,
      known_indels_sites_indices = known_indels_sites_indices,
      ref_dict = ref_dict,
      ref_fasta = ref_fasta,
      ref_fasta_index = ref_fasta_index
    }

  call Mutect2TumorOnly {
      input:
        input_bam = ApplyBaseRecalibrator.recalibrated_bam,
        input_bam_index = ApplyBaseRecalibrator.recalibrated_bai,
        ref_dict = ref_dict,
        ref_fasta = ref_fasta,
        ref_fasta_index = ref_fasta_index,
        genomeReference = af_only_gnomad,
        genomeReferenceIndex = af_only_gnomad_index
    }
  
  call annovar {
      input:
        input_vcf = Mutect2TumorOnly.output_vcf,
        ref_name = ref_name,
        annovarTAR = annovarTAR,
        annovar_operation = annovar_operation,
        annovar_protocols = annovar_protocols
    }
  
  # Outputs that will be retained when execution is complete
  output {
    File alignedBamSorted = BwaMem.analysisReadySorted
    File markDuplicates_bam = MarkDuplicates.markDuplicates_bam
    File markDuplicates_bai = MarkDuplicates.markDuplicates_bai
    File analysisReadyBam = ApplyBaseRecalibrator.recalibrated_bam 
    File analysisReadyIndex = ApplyBaseRecalibrator.recalibrated_bai
    File Mutect_Vcf = Mutect2TumorOnly.output_vcf
    File Mutect_VcfIndex = Mutect2TumorOnly.output_vcf_index
    File Mutect_AnnotatedVcf = annovar.output_annotated_vcf
    File Mutect_AnnotatedTable = annovar.output_annotated_table
  }
}



# TASK DEFINITIONS

# Align fastq file to the reference genome
task BwaMem {
  input {
    File input_fastq
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
  }
  
  String base_file_name = basename(input_fastq, ".fastq")
  String ref_fasta_local = basename(ref_fasta)
  String read_group_id = "ID:" + base_file_name
  String sample_name = "SM:" + base_file_name
  String platform = "illumina"
  String platform_info = "PL:" + platform   ## Create the platform information


  command <<<
    set -eo pipefail

    mv ~{ref_fasta} .
    mv ~{ref_fasta_index} .
    mv ~{ref_dict} .
    mv ~{ref_amb} .
    mv ~{ref_ann} .
    mv ~{ref_bwt} .
    mv ~{ref_pac} .
    mv ~{ref_sa} .

    bwa mem \
      -p -v 3 -t 16 -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
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
    docker: "fredhutch/bwa:0.7.17"
  }
}

## Mark duplicates
task MarkDuplicates {
  input {
    File input_bam
  }

  String base_file_name = basename(input_bam, ".sorted_query_aligned.bam")

  command <<<
    gatk MarkDuplicates \
      --INPUT ~{input_bam} \
      --OUTPUT ~{base_file_name}.duplicates_marked.bam \
      --METRICS_FILE ~{base_file_name}.duplicate_metrics \
      --CREATE_INDEX true \
      --OPTICAL_DUPLICATE_PIXEL_DISTANCE 100 \
      --VALIDATION_STRINGENCY SILENT
  >>>

  runtime {
    docker: "broadinstitute/gatk:4.1.4.0"
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
    File ref_dict
    File ref_fasta
    File ref_fasta_index
  }
  
  String base_file_name = basename(input_bam, ".duplicates_marked.bam")
  
  String ref_fasta_local = basename(ref_fasta)
  String dbSNP_vcf_local = basename(dbSNP_vcf)
  String known_indels_sites_VCFs_local = basename(known_indels_sites_VCFs)


  command <<<
  set -eo pipefail

  mv ~{ref_fasta} .
  mv ~{ref_fasta_index} .
  mv ~{ref_dict} .

  mv ~{dbSNP_vcf} .
  mv ~{dbSNP_vcf_index} .

  mv ~{known_indels_sites_VCFs} .
  mv ~{known_indels_sites_indices} .

  samtools index ~{input_bam}

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
      

  ## finds the current sort order of this bam file
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
    docker: "broadinstitute/gatk:4.1.4.0"
  }
}



# Mutect 2 calling

task Mutect2TumorOnly {
  input {
    File input_bam
    File input_bam_index
    File ref_dict
    File ref_fasta
    File ref_fasta_index
    File genomeReference
    File genomeReferenceIndex
  }

    String base_file_name = basename(input_bam, ".recal.bam")
    String ref_fasta_local = basename(ref_fasta)
    String genomeReference_local = basename(genomeReference)

command <<<
    set -eo pipefail

    mv ~{ref_fasta} .
    mv ~{ref_fasta_index} .
    mv ~{ref_dict} .
    mv ~{genomeReference} .
    mv ~{genomeReferenceIndex} .

    gatk --java-options "-Xms16g" Mutect2 \
      -R ~{ref_fasta_local} \
      -I ~{input_bam} \
      -O preliminary.vcf.gz \
      --germline-resource ~{genomeReference_local} \
     
    gatk --java-options "-Xms16g" FilterMutectCalls \
      -V preliminary.vcf.gz \
      -O ~{base_file_name}.mutect2.vcf.gz \
      -R ~{ref_fasta_local} \
      --stats preliminary.vcf.gz.stats \
     
>>>

runtime {
    docker: "broadinstitute/gatk:4.1.4.0"
    memory: "24 GB"
    cpu: 1
  }

output {
    File output_vcf = "${base_file_name}.mutect2.vcf.gz"
    File output_vcf_index = "${base_file_name}.mutect2.vcf.gz.tbi"
  }

}




# annotate with annovar
task annovar {
  input {
  File input_vcf
  String ref_name
  File annovarTAR
  String annovar_protocols
  String annovar_operation
}
  String base_vcf_name = basename(input_vcf, ".vcf.gz")
  
  command <<<
  set -eo pipefail
  
  tar -xzvf ~{annovarTAR}
  
  perl annovar/table_annovar.pl ~{input_vcf} annovar/humandb/ \
    -buildver ~{ref_name} \
    -outfile ~{base_vcf_name} \
    -remove \
    -protocol ~{annovar_protocols} \
    -operation ~{annovar_operation} \
    -nastring . -vcfinput
>>>
  runtime {
    docker : "perl:5.28.0"
    cpu: 1
    memory: "2GB"
  }
  output {
    File output_annotated_vcf = "${base_vcf_name}.${ref_name}_multianno.vcf"
    File output_annotated_table = "${base_vcf_name}.${ref_name}_multianno.txt"
  }
}
```

<iframe src="https://docs.google.com/forms/d/e/1FAIpQLSeEKGWTJOowBhFlWftPUjFU8Rfj-d9iXIHENyd8_HGS8PM7kw/viewform?embedded=true" width="640" height="886" frameborder="0" marginheight="0" marginwidth="0">Loading…</iframe>
