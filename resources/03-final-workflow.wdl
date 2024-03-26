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
   
  # Outputs that will be retained when execution is complete
  output {
    File alignedBamSorted = BwaMem.analysisReadySorted
  }

  parameter_meta {
    sampleFastq: "Sample .fastq (expects Illumina)"
    ref_fasta: "Reference genome to align reads to"
    ref_fasta_index: "Reference genome index file (created by bwa index)"
    ref_dict: "Reference genome dictionary file (created by bwa index)"
    ref_amb: "Reference genome non-ATCG file (created by bwa index)"
    ref_ann: "Reference genome ref seq annotation file (created by bwa index)"
    ref_bwt: "Reference genome binary file (created by bwa index)"
    ref_pac: "Reference genome binary file (created by bwa index)"
    ref_sa: "Reference genome binary file (created by bwa index)"
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

    mv "~{ref_fasta}" .
    mv "~{ref_fasta_index}" .
    mv "~{ref_dict}" .
    mv "~{ref_amb}" .
    mv "~{ref_ann}" .
    mv "~{ref_bwt}" .
    mv "~{ref_pac}" .
    mv "~{ref_sa}" .

    bwa mem \
      -p -v 3 -t 16 -M -R '@RG\t~{read_group_id}\t~{sample_name}\t~{platform_info}' \
      "~{ref_fasta_local}" "~{input_fastq}" > "~{base_file_name}.sam"
    samtools view -1bS -@ 15 -o "~{base_file_name}.aligned.bam" "~{base_file_name}.sam"
    samtools sort -n -@ 15 -o "~{base_file_name}.sorted_query_aligned.bam" "~{base_file_name}.aligned.bam"

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