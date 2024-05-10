

# Task Aliasing

Right now, we have developed our workflow for only tumor samples of a patient, but our mutation caller Mutect2 performs best when each tumor is matched with a normal sample. Therefore, in order to make best use of Mutect2, we want to run a similar analysis on the normal samples as well, using tasks such as BwaMem, MarkDuplicates, and ApplyBaseRecalibrator. We could write new tasks for the normal samples, but they are run exactly the same as the tumor samples: we would like to reuse our existing tasks for these tumor samples.

WDL has a feature that allows you to reuse the same task repeatedly through your workflow: **task aliasing**.
Task aliasing allows for the re-use of task definitions within the same workflow under different names, or "aliases". For example, our task for alignment, "BwaMem", can be aliased for both tumor and normal samples. This way, you don't need to copy and paste the same task definition multiple times, and when you modify the the task definition, all aliases will be updated. 



## Aliasing your first task

We first demonstrate task aliasing for tumor-normal matched somatic mutation calling in which we use the same normal sample for both tumor samples. This implies that we have taken multiple tumor samples from the same patient, and we're comparing all of them against a single normal sample. This is easy to write, but not a very common analysis. After this example, we follow up with a more sophisticated tumor-normal matched somatic mutation calling in which each patient has unique paired tumor-normal samples. This is the popular way of calling somatic mutation. 


You can only alias a task that is already defined, so we will start with aliasing the BwaMem task for normal samples rather than writing a new BwaMem task specifically for normal samples. We want to do this so it can run this task on the "normal" samples and store them separately. 

First, make sure that in your workflow input, you reference to the normal sample as input.

```
workflow mutation_calling {
  input {
    ...
    File normalFastq
...
  }
```

Then, you need to call the task you want to alias and use `as` to the `alias_of_your_choice`. Within the task, you need to make sure that all the inputs reflect the new variable, so `input_fastq` is directed to `normalFastq`. 

```
  call BwaMem as normalBwaMem {
    input:
      input_fastq = normalFastq,
      refGenome = refGenome
  }
```

In the output of the workflow, you also want to make sure that in you are saving the appropriate outputs to reflect the task alias. 

```
output {
  File normalalignedBamSorted = normalBwaMem.analysisReadySorted
}
```

## Aliasing other tasks

We can do this for the other two tasks in our workflow as well for the normal sample:

```
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
```

After adding these steps to the workflow, we will have our normal sample aligned and recalibrated. Together with the tumor sample, we can use the paired version of Mutect2 via the new `Mutect2Paired` task. 



<details>

<summary><b>The workflow so far using the same normal sample for tumor-normal mutation calling. </b></summary>

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
      refGenome = refGenome
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
      -p -v 3 -t 16 -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
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
  
    perl /annovar/table_annovar.pl "~{input_vcf}" /annovar/humandb/ \
      -buildver "~{ref_name}" \
      -outfile "~{base_vcf_name}" \
      -remove \
      -protocol "~{annovar_protocols}" \
      -operation "~{annovar_operation}" \
      -nastring . -vcfinput
  >>>
  runtime {
    docker : "ghcr.io/getwilds/annovar:${ref_name}"
    cpu: 1
    memory: "2GB"
  }
  output {
    File output_annotated_vcf = "~{base_vcf_name}.${ref_name}_multianno.vcf"
    File output_annotated_table = "~{base_vcf_name}.${ref_name}_multianno.txt"
  }
}

```

</details> 

## Paired tumor normal calling

Now that we are comfortable with task aliasing, we follow up with a more sophisticated tumor-normal matched somatic mutation calling in which each patient has unique paired tumor-normal samples. In order to do so, we need to ensure that each patient has an unique tumor and normal sample. We could modify our workflow inputs to be: 

```
workflow mutation_calling {
  input {
    Array[File] tumorSamples
    Array[file] normalSamples
    ...
  }
}
```

but that would be a bit awkward to scatter through, as we would need to create a separate index to keep track of which sample we are using in the array of `tumorSamples` and `normalSamples`.

Instead, we write a struct for our paired samples:

```
struct pairedSample {
  File tumorSample
  File normalSample
}
```

so that in our workflow inputs, we use an array of `pairedSample`:

```
workflow mutation_calling {
  input {
    Array[pairedSample] samples
    ...
  }
}
```

and we can scatter on `samples`. Within our scatter, we use task aliasing to call tumor-specific and normal-specific tasks until `Mutect2Paired` and `annovar`. 

```
scatter (sample in samples) {

    #Tumors
    call BwaMem as tumorBwaMem {
      input:
        input_fastq = sample.tumorSample,
        refGenome = refGenome
    }

    #Normals
    call BwaMem as normalBwaMem {
      input:
        input_fastq = sample.normalSample,
        refGenome = refGenome
    }
    
    ...
   
}
```

Putting it together:

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

struct pairedSample {
  File tumorSample
  File normalSample
}


workflow mutation_calling {
  input {
    Array[pairedSample] samples

    referenceGenome refGenome
    
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

 
  # Scatter for each sample in samples
  scatter (sample in samples) {

    #Tumors
    call BwaMem as tumorBwaMem {
      input:
        input_fastq = sample.tumorSample,
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

    #Normals
    call BwaMem as normalBwaMem {
      input:
        input_fastq = sample.normalSample,
        refGenome = refGenome
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

    #Paired Tumor-Normal calling
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
    Array[File] normalalignedBamSorted = normalBwaMem.analysisReadySorted
    Array[File] normalmarkDuplicates_bam = normalMarkDuplicates.markDuplicates_bam
    Array[File] normalmarkDuplicates_bai = normalMarkDuplicates.markDuplicates_bai
    Array[File] normalanalysisReadyBam = normalApplyBaseRecalibrator.recalibrated_bam 
    Array[File] normalanalysisReadyIndex = normalApplyBaseRecalibrator.recalibrated_bai
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
      -p -v 3 -t 16 -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
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

Now we have a complete workflow that reflects our original plan in [Defining a workflow plan](https://hutchdatascience.org/WDL_Workflows_Guide/defining-a-workflow-plan.html)!


<iframe src="https://docs.google.com/forms/d/e/1FAIpQLSeEKGWTJOowBhFlWftPUjFU8Rfj-d9iXIHENyd8_HGS8PM7kw/viewform?embedded=true" width="640" height="886" frameborder="0" marginheight="0" marginwidth="0">Loading…</iframe>
