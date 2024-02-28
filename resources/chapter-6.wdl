version 1.0
## Samples:
## MOLM13: Normal sample
##
## 
## Workflow developed by Sitapriya Moorthi @ Fred Hutch LMD: 01/10/24 for use by DaSL @ Fred Hutch.
## Workflow updated on : 02/13/24 by Sitapriya Moorthi

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
    
    File af_only_gnomad
    File af_only_gnomad_index
    
    File annovarTAR
    String annovar_protocols
    String annovar_operation

    Int bwa_mem_threads
  }
 
  # Scatter for "tumor" samples   
  scatter (tumorFastq in tumorSamples) {
    call BwaMem as sampleBwaMem {
      input:
        input_fastq = tumorFastq,
        refGenome = refGenome
    }
    
    call MarkDuplicates as sampleMarkDuplicates {
      input:
        input_bam = sampleBwaMem.analysisReadySorted
    }

    call ApplyBaseRecalibrator as sampleApplyBaseRecalibrator{
      input:
        input_bam = sampleMarkDuplicates.markDuplicates_bam,
        input_bam_index = sampleMarkDuplicates.markDuplicates_bai,
        dbSNP_vcf = dbSNP_vcf,
        dbSNP_vcf_index = dbSNP_vcf_index,
        known_indels_sites_VCFs = known_indels_sites_VCFs,
        known_indels_sites_indices = known_indels_sites_indices,
        refGenome = refGenome
    }

    call Mutect2 {
      input:
        tumor_bam = sampleApplyBaseRecalibrator.recalibrated_bam,
        tumor_bam_index = sampleApplyBaseRecalibrator.recalibrated_bai,
        normal_bam = normalApplyBaseRecalibrator.recalibrated_bam,
        normal_bam_index = normalApplyBaseRecalibrator.recalibrated_bai,
        refGenome = refGenome,
        genomeReference = af_only_gnomad,
        genomeReferenceIndex = af_only_gnomad_index
    }

  call annovar {
    input:
      input_vcf = Mutect2.output_vcf,
      ref_name = refGenome.ref_name,
      annovarTAR = annovarTAR,
      annovar_operation = annovar_operation,
      annovar_protocols = annovar_protocols
  }
}

  output {
    Array[File] samplealignedBamSorted = sampleBwaMem.analysisReadySorted
    Array[File] samplemarkDuplicates_bam = sampleMarkDuplicates.markDuplicates_bam
    Array[File] samplemarkDuplicates_bai = sampleMarkDuplicates.markDuplicates_bai
    Array[File] sampleanalysisReadyBam = sampleApplyBaseRecalibrator.recalibrated_bam 
    Array[File] sampleanalysisReadyIndex = sampleApplyBaseRecalibrator.recalibrated_bai
    Array[File] Mutect_Vcf = Mutect2.output_vcf
    Array[File] Mutect_VcfIndex = Mutect2.output_vcf_index
    Array[File] Mutect_AnnotatedVcf = annovar.output_annotated_vcf
    Array[File] Mutect_AnnotatedTable = annovar.output_annotated_table
  }
}
# TASK DEFINITIONS

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
  String platform = "illumina"
  String platform_info = "PL:" + platform   # Create the platform information


  command <<<
    set -eo pipefail

    #can we iterate through a struct??
    mv ~{refGenome.ref_fasta} .
    mv ~{refGenome.ref_fasta_index} .
    mv ~{refGenome.ref_dict} .
    mv ~{refGenome.ref_amb} .
    mv ~{refGenome.ref_ann} .
    mv ~{refGenome.ref_bwt} .
    mv ~{refGenome.ref_pac} .
    mv ~{refGenome.ref_sa} .

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

# Mark duplicates (not SPARK, for some reason that does something weird)
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
    docker: "broadinstitute/gatk:4.1.4.0"
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
    docker: "broadinstitute/gatk:4.1.4.0"
  }
}


# Mutect 2 calling tumor-normal

task Mutect2 {
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
  String base_file_name_normal = basename(normal_bam, ".recal.bam")
  String ref_fasta_local = basename(refGenome.ref_fasta)
  String genomeReference_local = basename(genomeReference)

  command <<<
    set -eo pipefail

    mv ~{refGenome.ref_fasta} .
    mv ~{refGenome.ref_fasta_index} .
    mv ~{refGenome.ref_dict} .

    mv ~{genomeReference} .
    mv ~{genomeReferenceIndex} .

    gatk --java-options "-Xms16g" Mutect2 \
      -R ~{ref_fasta_local} \
      -I ~{tumor_bam} \
      -I ~{normal_bam} \
      -O preliminary.vcf.gz \
      --germline-resource ~{genomeReference_local} \

    gatk --java-options "-Xms16g" FilterMutectCalls \
      -V preliminary.vcf.gz \
      -O ~{base_file_name_tumor}.mutect2.vcf.gz \
      -R ~{ref_fasta_local} \
      --stats preliminary.vcf.gz.stats \

>>>

  runtime {
    docker: "broadinstitute/gatk:4.1.4.0"
    memory: "24 GB"
    cpu: 1
  }

  output {
    File output_vcf = "${base_file_name_tumor}.mutect2.vcf.gz"
    File output_vcf_index = "${base_file_name_tumor}.mutect2.vcf.gz.tbi"
  }
}

# annotate with annovar mutation calling outputs
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
