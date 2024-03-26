version 1.0

workflow mutation_calling {
  input {
    File sampleFastq

    # Reference genome
    File ref_fasta
    File ref_fasta_index
    File ref_dict
    File ref_amb
    File ref_ann
    File ref_bwt
    File ref_pac
    File ref_sa
    String ref_name

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

  parameter_meta {
    sampleFastq: "Tumor .fastq (expects Illumina)"

    ref_fasta: "Reference genome to align reads to"
    ref_fasta_index: "Reference genome index file (created by bwa index)"
    ref_dict: "Reference genome dictionary file (created by bwa index)"
    ref_amb: "Reference genome non-ATCG file (created by bwa index)"
    ref_ann: "Reference genome ref seq annotation file (created by bwa index)"
    ref_bwt: "Reference genome binary file (created by bwa index)"
    ref_pac: "Reference genome binary file (created by bwa index)"
    ref_sa: "Reference genome binary file (created by bwa index)"
    ref_name: "Reference genome name (hg19, hg37, etc.)"

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
  String platform_info = "PL:illumina"


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
      --INPUT ~{input_bam} \
      --OUTPUT ~{base_file_name}.duplicates_marked.bam \
      --METRICS_FILE ~{base_file_name}.duplicate_metrics \
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
      

  # finds the current sort order of this bam file
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

# Variant calling via mutect2 (tumor-only mode)
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
    docker: "ghcr.io/getwilds/gatk:4.3.0.0"
    memory: "24 GB"
    cpu: 1
  }

output {
    File output_vcf = "${base_file_name}.mutect2.vcf.gz"
    File output_vcf_index = "${base_file_name}.mutect2.vcf.gz.tbi"
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
  
  
  perl annovar/table_annovar.pl ~{input_vcf} annovar/humandb/ \
    -buildver ~{ref_name} \
    -outfile ~{base_vcf_name} \
    -remove \
    -protocol ~{annovar_protocols} \
    -operation ~{annovar_operation} \
    -nastring . -vcfinput
>>>
  runtime {
    docker : "ghcr.io/getwilds/annovar:${ref_name}"
    cpu: 1
    memory: "2GB"
  }
  output {
    File output_annotated_vcf = "${base_vcf_name}.${ref_name}_multianno.vcf"
    File output_annotated_table = "${base_vcf_name}.${ref_name}_multianno.txt"
  }
}